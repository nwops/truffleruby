# Copyright (c) 2017 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
#
# Eclipse Public License version 1.0, or
# GNU General Public License version 2, or
# GNU Lesser General Public License version 2.1.

# Split from rbconfig.rb since we need to do expensive tasks like checking the
# clang and opt versions.

require 'rbconfig'

search_paths = {}
if Truffle::Platform.darwin?
  if Dir.exist?('/usr/local/opt/llvm@4/bin') # Homebrew
    search_paths['/usr/local/opt/llvm@4/bin/'] = '/usr/local/opt/llvm@4/bin'
  elsif Dir.exist?('/opt/local/libexec/llvm-4.0/bin') # MacPorts
    search_paths['/opt/local/libexec/llvm-4.0/bin/'] = '/opt/local/libexec/llvm-4.0/bin'
  end
end
search_paths[''] = '$PATH'

# First, find in which prefix clang and opt are available.
# We want to use both tools from the same prefix.
versions = {}
prefix = search_paths.keys.find do |search_path|
  %w[clang opt].all? do |tool|
    tool_path = "#{search_path}#{tool}"
    begin
      versions[tool_path] = `#{tool_path} --version`
    rescue Errno::ENOENT
      false # Not found
    end
  end
end

unless prefix
  search_paths_description = search_paths.values.join(' or ')
  abort "The clang and opt tools, part of LLVM, do not appear to be available in #{search_paths_description}.\n" +
        'You need to install LLVM, see https://github.com/oracle/truffleruby/blob/master/doc/user/installing-llvm.md'
end

clang = "#{prefix}clang"
opt = "#{prefix}opt"
extra_cflags = nil

# Check the versions
versions.each_pair do |tool, version|
  if version =~ /\bversion (\d+\.\d+\.\d+)/
    major, minor, _patch = $1.split('.').map(&:to_i)
    if (major == 3 && minor >= 8) || (major == 4 && minor == 0)
      # OK
    elsif major >= 5
      extra_cflags = '-Xclang -disable-O0-optnone'
    else
      abort "unsupported #{tool} version: #{$1}, see https://github.com/oracle/truffleruby/blob/master/doc/user/installing-llvm.md"
    end
  else
    abort "cannot parse the version of #{tool} from #{version.inspect}"
  end
end

opt_passes = ['-always-inline', '-mem2reg', '-constprop'].join(' ')

debugflags = '-g' # Show debug information such as line numbers in backtrace
warnflags = [
  '-Wimplicit-function-declaration', # To make missing C ext functions clear
  '-Wno-unknown-warning-option',     # If we're on an earlier version of clang without a warning option, ignore it
  '-Wno-int-conversion',             # MRI has VALUE defined as long while we have it as void*
  '-Wno-int-to-pointer-cast',        # Same as above
  '-Wno-unused-value',               # RB_GC_GUARD leaves
  '-Wno-incompatible-pointer-types', # Fix byebug 8.2.1 compile (st_data_t error)
  '-ferror-limit=500'
].join(' ')

cc = clang
cxx = "#{clang}++"

cflags = "#{debugflags} #{warnflags} -c -emit-llvm"
cflags = "#{extra_cflags} #{cflags}" if extra_cflags
cxxflags = "#{cflags} -stdlib=libc++"

cext_dir = "#{RbConfig::CONFIG['libdir']}/cext"

expanded = RbConfig::CONFIG
mkconfig = RbConfig::MAKEFILE_CONFIG

common = {
  'CC' => cc,
  'CPP' => cc,
  'CXX' => cxx,
  'debugflags' => debugflags,
  'warnflags' => warnflags,
  'CFLAGS' => cflags,
  'CXXFLAGS' => cxxflags
}
expanded.merge!(common)
mkconfig.merge!(common)

mkconfig['COMPILE_C']   = "ruby #{cext_dir}/preprocess.rb $< | $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG) -xc - -o $@ && #{opt} #{opt_passes} $@ -o $@"
mkconfig['COMPILE_CXX'] = "ruby #{cext_dir}/preprocess.rb $< | $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG) -xc++ - -o $@ && #{opt} #{opt_passes} $@ -o $@"

# From mkmf.rb: "$(LDSHARED) #{OUTFLAG}$@ $(OBJS) $(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)"
# The only difference is we use linker.rb instead of LDSHARED
mkconfig['LINK_SO'] = "#{RbConfig.ruby} #{cext_dir}/linker.rb -o $@ $(OBJS) $(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)"

cflags_for_try_link = "#{debugflags} #{warnflags}"
# From mkmf.rb: "$(CC) #{OUTFLAG}#{CONFTEST}#{$EXEEXT} $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"
mkconfig['TRY_LINK'] = "#{cc} -o conftest $(INCFLAGS) $(CPPFLAGS) #{cflags_for_try_link} #{cext_dir}/ruby.o #{cext_dir}/sulongmock.o $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"

%w[COMPILE_C COMPILE_CXX LINK_SO TRY_LINK].each do |key|
  expanded[key] = mkconfig[key].gsub(/\$\((\w+)\)/) { expanded.fetch($1, $&) }
end
