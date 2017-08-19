#!/usr/bin/env bash

pkgdir=$PWD/build/pkg

_target=arm-none-eabi
_pkgver_binutils=2.29
_pkgver_gcc=7.2.0
_pkgver_newlib=2.5.0
_pkgver_gdb=8.0

if [ $# == 0 ]; then
  build_flag="all"
else
  build_flag="$1"
fi

# General setup
mkdir -p build/pkg
PATH=$PATH:$pkgdir
pushd build

binutils_prepare() {
  cd binutils-$pkgver
  sed -i "/ac_cpp=/s/\$CPPFLAGS/\$CPPFLAGS -O2/" libiberty/configure
}

binutils_build() {
  cd binutils-$pkgver

  ./configure --target=$_target \
              --with-sysroot=/usr/$_target \
              --prefix=/usr \
              --enable-multilib \
              --enable-interwork \
              --with-gnu-as \
              --with-gnu-ld \
              --disable-nls \
              --enable-plugins

  make -j$(nproc)
}

binutils_check() {
  cd binutils-$pkgver

  # unset LDFLAGS as testsuite makes assumptions about which ones are active
  # do not abort on errors - manually check log files
  make LDFLAGS="" -k check
}

binutils_package() {
  cd binutils-$pkgver

  make DESTDIR="$pkgdir" install

  # Remove file conflicting with host binutils and manpages for MS Windows tools
  rm "$pkgdir"/usr/share/man/man1/arm-none-eabi-{dlltool,nlmconv,windres,windmc}*

  # Remove info documents that conflict with host version
  rm -r "$pkgdir"/usr/share/info
}

if [ "$build_flag" = "all" ] || [ "$build_flag" = "binutils" ]; then
  # binutils setup
  mkdir binutils
  pushd binutils
  srcdir=$PWD
  pkgver=${_pkgver_binutils}

  # binutils download
  wget ftp://ftp.gnu.org/gnu/binutils/binutils-$pkgver.tar.bz2
  tar -xf binutils-$pkgver.tar.bz2

  cd $srcdir
  binutils_prepare
  cd $srcdir
  binutils_build
  cd $srcdir
  binutils_check
  cd $srcdir
  binutils_package

  # binutils teardown
  popd
fi

gcc-stage1_prepare() {
  cd $_basedir

  # link isl for in-tree builds
  ln -s ../isl-$_islver isl

  echo $pkgver > gcc/BASE-VER

  # hack! - some configure tests for header files using "$CPP $CPPFLAGS"
  sed -i "/ac_cpp=/s/\$CPPFLAGS/\$CPPFLAGS -O2/" {libiberty,gcc}/configure

  patch -p1 < $srcdir/enable-with-multilib-list-for-arm.patch

  mkdir $srcdir/build-gcc
}

gcc-stage1_build() {
  cd $srcdir/build-gcc
  export CFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections'
  export CXXFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections'

  $srcdir/$_basedir/configure \
    --target=$_target \
    --prefix=/usr \
    --with-sysroot=/usr/$_target \
    --with-native-system-header-dir=/include \
    --libexecdir=/usr/lib \
    --enable-languages=c,c++ \
    --enable-plugins \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-gnu-as \
    --with-gnu-ld \
    --with-system-zlib \
    --with-newlib \
    --with-headers=/usr/$_target/include \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-gmp \
    --with-mpfr \
    --with-mpc \
    --with-isl \
    --with-libelf \
    --enable-gnu-indirect-function \
    --with-host-libstdcxx='-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm' \
    --with-pkgversion='Arch Repository' \
    --with-bugurl='https://bugs.archlinux.org/' \
    --with-multilib-list=armv6-m,armv7-m,armv7e-m,armv7-r

  make all-gcc all-target-libgcc INHIBIT_LIBC_CFLAGS='-DUSE_TM_CLONE_REGISTRY=0' -j$(nproc)
}

gcc-stage1_package() {
  cd $srcdir/build-gcc
  make DESTDIR="$pkgdir" install all-gcc all-target-libgcc -j1

  # strip target binaries
  find "$pkgdir"/usr/lib/gcc/$_target/$pkgver "$pkgdir"/usr/$_target/lib -type f -and \( -name \*.a -or -name \*.o \) -exec $_target-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc '{}' \;

  # strip host binaries
  find "$pkgdir"/usr/bin/ "$pkgdir"/usr/lib/gcc/$_target/$pkgver -type f -and \( -executable \) -exec strip '{}' \;

  # Remove files that conflict with host gcc package
  rm -r "$pkgdir"/usr/share/man/man7
  rm -r "$pkgdir"/usr/share/info
}

if [ "$build_flag" = "all" ] || [ "$build_flag" = "gcc-stage1" ]; then
  # gcc-stage1 setup
  mkdir gcc-stage1
  pushd gcc-stage1
  srcdir=$PWD
  pkgver=${_pkgver_gcc}
  _islver=0.18
  if [ -n "$_snapshot" ]; then
    _basedir=gcc-$_snapshot
  else
    _basedir=gcc-$pkgver
  fi

  # gcc-stage1 download
  wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-$pkgver/gcc-$pkgver.tar.bz2
  wget http://isl.gforge.inria.fr/isl-$_islver.tar.bz2
  cp ../../enable-with-multilib-list-for-arm.patch .
  tar -xf gcc-$pkgver.tar.bz2
  tar -xf isl-$_islver.tar.bz2

  cd $srcdir
  gcc-stage1_prepare
  cd $srcdir
  gcc-stage1_build
  cd $srcdir
  gcc-stage1_package

  # gcc-stage1 teardown
  popd
fi

newlib_build() {
  rm -rf build-{newlib,nano}
  mkdir build-{newlib,nano}

  export CFLAGS_FOR_TARGET='-g -O2 -ffunction-sections -fdata-sections'
  cd "$srcdir"/build-newlib
  ../newlib-$_upstream_ver/configure \
    --target=$_target \
    --prefix=/usr \
    --disable-newlib-supplied-syscalls \
    --disable-nls \
    --enable-newlib-io-long-long \
    --enable-newlib-register-fini
  make -j$(nproc)

  export CFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections'
  cd "$srcdir"/build-nano
  ../newlib-$_upstream_ver/configure \
    --target=$_target \
    --prefix=/usr \
    --disable-newlib-supplied-syscalls \
    --disable-nls \
    --enable-newlib-reent-small           \
    --disable-newlib-fvwrite-in-streamio  \
    --disable-newlib-fseek-optimization   \
    --disable-newlib-wide-orient          \
    --enable-newlib-nano-malloc           \
    --disable-newlib-unbuf-stream-opt     \
    --enable-lite-exit                    \
    --enable-newlib-global-atexit         \
    --enable-newlib-nano-formatted-io
  make -j$(nproc)
}

newlib_package() {
  cd "$srcdir"/build-nano
  make DESTDIR="$pkgdir" install -j1
  find "$pkgdir" -regex ".*/lib\(c\|g\|rdimon\)\.a" -exec rename .a _nano.a '{}' \;

  cd "$srcdir"/build-newlib
  make DESTDIR="$pkgdir" install -j1

  find "$pkgdir"/usr/$_target/lib \( -name "*.a" -or -name "*.o" \) -exec $_target-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc '{}' \;

  install -d "$pkgdir"/usr/share/licenses/$pkgname/
  install -m644 -t "$pkgdir"/usr/share/licenses/$pkgname/ "$srcdir"/newlib-$_upstream_ver/COPYING*
}

if [ "$build_flag" = "all" ] || [ "$build_flag" = "newlib" ]; then
  # newlib setup
  mkdir newlib
  pushd newlib
  srcdir=$PWD
  pkgver=${_pkgver_newlib}
  _upstream_ver=2.5.0

  # newlib download
  wget ftp://sourceware.org/pub/newlib/newlib-$_upstream_ver.tar.gz
  tar -xf newlib-$_upstream_ver.tar.gz

  cd $srcdir
  newlib_build
  cd $srcdir
  newlib_package

  # newlib teardown
  popd
fi

gcc_prepare() {
  cd $_basedir

  # link isl for in-tree builds
  ln -s ../isl-$_islver isl

  echo $pkgver > gcc/BASE-VER

  # hack! - some configure tests for header files using "$CPP $CPPFLAGS"
  sed -i "/ac_cpp=/s/\$CPPFLAGS/\$CPPFLAGS -O2/" {libiberty,gcc}/configure

  patch -p1 < $srcdir/enable-with-multilib-list-for-arm.patch

  mkdir $srcdir/build-gcc
}

gcc_build() {
  cd $srcdir/build-gcc
  export CFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections'
  export CXXFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections'

  $srcdir/$_basedir/configure \
    --target=$_target \
    --prefix=/usr \
    --with-sysroot=/usr/$_target \
    --with-native-system-header-dir=/include \
    --libexecdir=/usr/lib \
    --enable-languages=c,c++ \
    --enable-plugins \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-gnu-as \
    --with-gnu-ld \
    --with-system-zlib \
    --with-newlib \
    --with-headers=/usr/$_target/include \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-gmp \
    --with-mpfr \
    --with-mpc \
    --with-isl \
    --with-libelf \
    --enable-gnu-indirect-function \
    --with-host-libstdcxx='-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm' \
    --with-pkgversion='Arch Repository' \
    --with-bugurl='https://bugs.archlinux.org/' \
    --with-multilib-list=armv6-m,armv7-m,armv7e-m,armv7-r

  make INHIBIT_LIBC_CFLAGS='-DUSE_TM_CLONE_REGISTRY=0' -j$(nproc)
}

gcc_package() {
  cd $srcdir/build-gcc
  make DESTDIR="$pkgdir" install -j1

  # strip target binaries
  find "$pkgdir"/usr/lib/gcc/$_target/$pkgver "$pkgdir"/usr/$_target/lib -type f -and \( -name \*.a -or -name \*.o \) -exec $_target-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc '{}' \;

  # strip host binaries
  find "$pkgdir"/usr/bin/ "$pkgdir"/usr/lib/gcc/$_target/$pkgver -type f -and \( -executable \) -exec strip '{}' \;

  # Remove files that conflict with host gcc package
  rm -r "$pkgdir"/usr/share/man/man7
  rm -r "$pkgdir"/usr/share/info
}

if [ "$build_flag" = "all" ] || [ "$build_flag" = "gcc" ]; then
  # gcc setup
  mkdir gcc
  pushd gcc
  srcdir=$PWD
  pkgver=${_pkgver_gcc}
  _islver=0.18
  if [ -n "$_snapshot" ]; then
    _basedir=gcc-$_snapshot
  else
    _basedir=gcc-$pkgver
  fi

  # gcc download
  wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-$pkgver/gcc-$pkgver.tar.bz2
  wget http://isl.gforge.inria.fr/isl-$_islver.tar.bz2
  cp ../../enable-with-multilib-list-for-arm.patch .
  tar -xf gcc-$pkgver.tar.bz2
  tar -xf isl-$_islver.tar.bz2

  cd $srcdir
  gcc_prepare
  cd $srcdir
  gcc_build
  cd $srcdir
  gcc_package

  # gcc teardown
  popd
fi

gdb_prepare() {
  cd gdb-$pkgver
  sed -i "/ac_cpp=/s/\$CPPFLAGS/\$CPPFLAGS -O2/" libiberty/configure
}

gdb_build() {
  cd gdb-$pkgver

  ./configure \
    --target=$_target \
    --prefix=/usr \
    --enable-languages=c,c++ \
    --enable-multilib \
    --enable-interwork \
    --with-system-readline \
    --disable-nls \
    --with-python=/usr/bin/python3 \
    --without-guile \
    --with-system-gdbinit=/etc/gdb/gdbinit

  make -j$(nproc)
}

gdb_package() {
  cd gdb-$pkgver

  make DESTDIR="$pkgdir" install

  # Following files conflict with 'gdb' package
  rm -r "$pkgdir"/usr/share/info
  rm -r "$pkgdir"/usr/share/gdb
  rm -r "$pkgdir"/usr/include/gdb
  rm -r "$pkgdir"/usr/share/man/man5
}

if [ "$build_flag" = "all" ] || [ "$build_flag" = "gdb" ]; then
  # gdb setup
  mkdir gdb
  pushd gdb
  srcdir=$PWD
  pkgver=${_pkgver_gdb}

  # gdb download
  wget ftp://ftp.gnu.org/gnu/gdb/gdb-$pkgver.tar.xz
  tar -xf gdb-$pkgver.tar.bz2

  cd $srcdir
  gdb_prepare
  cd $srcdir
  gdb_build
  cd $srcdir
  gdb_package

  # gdb teardown
  popd
fi

# General teardown
popd
