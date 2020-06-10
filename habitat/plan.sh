pkg_name=cinc-infra-client
pkg_origin=cinc
pkg_maintainer="The cinc Maintainers <maintainers@cinc.sh>"
pkg_description="The cinc Infra Client"
pkg_license=('Apache-2.0')
pkg_bin_dirs=(bin)
_chef_client_ruby="core/ruby27"
pkg_build_deps=(
  core/make
  core/gcc
  core/git
)
pkg_deps=(
  core/glibc
  $_chef_client_ruby
  core/libxml2
  core/libxslt
  core/libiconv
  core/xz
  core/zlib
  core/openssl
  core/cacerts
  core/libffi
  core/coreutils
  core/libarchive
)
pkg_svc_user=root

pkg_version() {
  cat "${SRC_PATH}/VERSION"
}

do_before() {
  do_default_before
  update_pkg_version
  # We must wait until we update the pkg_version to use the pkg_version
  pkg_filename="${pkg_name}-${pkg_version}.tar.gz"
}

do_download() {
  build_line "Locally creating archive of latest repository commit at ${HAB_CACHE_SRC_PATH}/${pkg_filename}"
  # source is in this repo, so we're going to create an archive from the
  # appropriate path within the repo and place the generated tarball in the
  # location expected by do_unpack
  ( cd "${SRC_PATH}" || exit_with "unable to enter hab-src directory" 1
    git archive --prefix="${pkg_name}-${pkg_version}/" --output="${HAB_CACHE_SRC_PATH}/${pkg_filename}" HEAD
  )
}

do_verify() {
  build_line "Skipping checksum verification on the archive we just created."
  return 0
}

do_prepare() {
  export OPENSSL_LIB_DIR=$(pkg_path_for openssl)/lib
  export OPENSSL_INCLUDE_DIR=$(pkg_path_for openssl)/include
  export SSL_CERT_FILE=$(pkg_path_for cacerts)/ssl/cert.pem
  openssl s_client -showcerts -verify 5 -connect free.fr:443 </dev/null | awk '/BEGIN/,/END/{if(/BEGIN/){a++}; certs[a]=(certs[a] "\n" $0)}; END {print certs[a]}' >> $SSL_CERT_FILE

  build_line "Setting link for /usr/bin/env to 'coreutils'"
  if [ ! -f /usr/bin/env ]; then
    ln -s "$(pkg_interpreter_for core/coreutils bin/env)" /usr/bin/env
  fi
}

do_build() {
  local _libxml2_dir
  local _libxslt_dir
  local _zlib_dir
  export CPPFLAGS
  export GEM_HOME
  export GEM_PATH
  export NOKOGIRI_CONFIG

  _libxml2_dir=$(pkg_path_for libxml2)
  _libxslt_dir=$(pkg_path_for libxslt)
  _zlib_dir=$(pkg_path_for zlib)

  CPPFLAGS="${CPPFLAGS} ${CFLAGS}"
  GEM_HOME=${pkg_prefix}/bundle
  GEM_PATH=${GEM_HOME}
  NOKOGIRI_CONFIG="--use-system-libraries \
    --with-zlib-dir=${_zlib_dir} \
    --with-xslt-dir=${_libxslt_dir} \
    --with-xml2-include=${_libxml2_dir}/include/libxml2 \
    --with-xml2-lib=${_libxml2_dir}/lib"

  build_line "Executing bundle install inside hab-cache path. ($CACHE_PATH/chef-config)"
  ( cd "$CACHE_PATH/chef-config" || exit_with "unable to enter hab-cache directory" 1
    bundle config --local build.nokogiri "${NOKOGIRI_CONFIG}"
    bundle config --local silence_root_warning 1
    _bundle_install "${pkg_prefix}/bundle"
  )

  build_line "Executing bundle install inside source path. ($SRC_PATH)"
  _bundle_install "${pkg_prefix}/bundle"
}

do_install() {
  build_line "Copying directories from source to pkg_prefix"
  mkdir -p "${pkg_prefix}/cinc"
  for dir in bin chef-bin chef-config chef-utils lib chef.gemspec Gemfile Gemfile.lock; do
    cp -rv "${SRC_PATH}/${dir}" "${pkg_prefix}/cinc/"
  done

  # If we generated them on install, bundler thinks our source is in $HAB_CACHE_SOURCE_PATH
  build_line "Generating binstubs with the correct path"
  ( cd "$pkg_prefix/cinc" || exit_with "unable to enter pkg prefix directory" 1
    _bundle_install \
      "${pkg_prefix}/bundle" \
      --local \
      --quiet \
      --binstubs "${pkg_prefix}/bin"
  )
  
  wrapper_links="chef-apply chef-client chef-shell chef-solo"
  link_target="cinc-wrapper"
  for link in $wrapper_links; do
    if [ ! -e ${pkg_prefix}/bin/$link ]; then
      build_line "Symlinking $link command to cinc-wrapper for compatibility..."
      ln -sf ${pkg_prefix}/bin/$link_target ${pkg_prefix}/bin/$link || error_exit "Cannot link $link_target to $PREFIX/bin/$link"
    fi
  done

  build_line "Fixing bin/ruby and bin/env interpreters"
  fix_interpreter "${pkg_prefix}/bin/*" core/coreutils bin/env
  fix_interpreter "${pkg_prefix}/bin/*" "$_chef_client_ruby" bin/ruby
}

do_end() {
  if [ "$(readlink /usr/bin/env)" = "$(pkg_interpreter_for core/coreutils bin/env)" ]; then
    build_line "Removing the symlink we created for '/usr/bin/env'"
    rm /usr/bin/env
  fi
}

do_strip() {
  return 0
}

# Helper function to wrap up some repetitive bundle install flags
_bundle_install() {
  local path
  path="$1"
  shift

  bundle install ${*:-} \
    --jobs "$(nproc)" \
    --without development:test:docgen \
    --path "$path" \
    --shebang="$(pkg_path_for "$_chef_client_ruby")/bin/ruby" \
    --no-clean \
    --retry 5 \
    --standalone
}
