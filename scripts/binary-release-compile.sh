#!/bin/sh
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

: ${ADVZIP:=advzip -4}
: ${GO:=go}
: ${LIPO:=lipo}

GOOS=$($GO env GOOS)
GOEXE=$($GO env GOEXE)

if [ $# -eq 0 ]; then
	set -- $($GO env GOARCH)
fi

case "$GOOS" in
	js)
		# HACK: Itch and Apache want a .wasm file extension, but GOEXE doesn't actually have that.
		GOEXE=.wasm
		;;
esac

case "$#" in
	1)
		GOARCH_SUFFIX=-$1
		;;
	*)
		GOARCH_SUFFIX=
		;;
esac

: ${AAAAXY_ZIPFILE:="aaaaxy-$GOOS$GOARCH_SUFFIX-$(sh scripts/version.sh gittag).zip"}

# It must be an absolute path as we use "cd" while creating the zip.
case "$AAAAXY_ZIPFILE" in
	/*)
		;;
	*)
		AAAAXY_ZIPFILE="$PWD/$AAAAXY_ZIPFILE"
		;;
esac

exec 3>&1
exec >&2

case "$GOOS" in
	darwin)
		appdir=packaging/
		app=AAAAXY.app
		prefix=packaging/AAAAXY.app/Contents/MacOS/
		buildtype=ziprelease
		;;
	js)
		appdir=.
		app="aaaaxy-$GOOS$GOARCH_SUFFIX$GOEXE index.html wasm_exec.js"
		prefix=
		buildtype=release
		;;
	*)
		appdir=.
		app=aaaaxy-$GOOS$GOARCH_SUFFIX$GOEXE
		prefix=
		buildtype=release
		;;
esac

# Remove possible leftovers from previous compiles that "make clean" won't get.
case "$prefix" in
	*/*)
		rm -rf "${prefix%/*}"
		mkdir -p "${prefix%/*}"
		;;
esac

if [ -n "$GOARCH_SUFFIX" ]; then
	eval "export CGO_ENV=\$CGO_ENV_$1"
	binary=${prefix}aaaaxy-$GOOS$GOARCH_SUFFIX$GOEXE
	GOARCH=$(GOARCH=$1 $GO env GOARCH) make BUILDTYPE=$buildtype BINARY="$binary" clean all
	unset CGO_ENV
else
	lipofiles=
	for arch in "$@"; do
		eval "export CGO_ENV=\$CGO_ENV_$arch"
		binary=${prefix}aaaaxy-$GOOS-$arch$GOEXE
		GOARCH=$(GOARCH=$arch $GO env GOARCH) make BUILDTYPE=$buildtype BINARY="$binary" clean all
		unset CGO_ENV
		lipofiles="$lipofiles $binary"
	done
	binary=${prefix}aaaaxy-$GOOS$GOEXE
	$LIPO -create $lipofiles -output "$binary"
	rm -f $lipofiles
fi

case "$GOOS" in
	darwin)
		sh scripts/build-macos-resources.sh
		;;
	js)
		# Pack in a form itch.io can use.
		cp aaaaxy.html index.html
		cp "$(cd / && GOOS=js GOARCH=wasm go env GOROOT)"/lib/wasm/wasm_exec.js .
		;;
esac

rm -f "$AAAAXY_ZIPFILE"
zip -r "$AAAAXY_ZIPFILE" \
	README.md LICENSE CONTRIBUTING.md \
	licenses
(
	cd "$appdir"
	zip -r "$AAAAXY_ZIPFILE" \
		$app
)
$ADVZIP -z "$AAAAXY_ZIPFILE"

case "$GOOS" in
	linux)
		arch=${GOARCH_SUFFIX#-}
		case "$arch" in
			amd64)
				arch=x86_64
				;;
			386)
				arch=x86
				;;
		esac
		sh scripts/build-appimage-resources.sh
		rm -rf packaging/AAAAXY.AppDir
		linuxdeploy-$(uname -m).AppImage \
			--appdir=packaging/AAAAXY.AppDir \
			-e "$app" \
			-d packaging/"$app".desktop \
			-i packaging/"$app".png
		mkdir -p packaging/AAAAXY.AppDir/usr/share/metainfo
		id=io.github.divverent.aaaaxy_${GOARCH_SUFFIX#-}
		cp packaging/"$id".metainfo.xml packaging/AAAAXY.AppDir/usr/share/metainfo/
		appimagetool-$(uname -m).AppImage \
			-u "gh-releases-zsync|divVerent|aaaaxy|latest|AAAAXY-$arch.AppImage.zsync" \
			packaging/AAAAXY.AppDir \
			"AAAAXY-$arch.AppImage"
		;;
esac

make clean

echo >&3 "$AAAAXY_ZIPFILE"
