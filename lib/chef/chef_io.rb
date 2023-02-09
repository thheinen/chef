require 'train' unless defined?(Train)
require 'stringio' unless defined?(StringIO)
require "etc" unless defined?(Etc)
require "fileutils" unless defined?(FileUtils)

require 'binding_of_caller'

class Chef
  class Client
    def self.transport_connection
      $transport_connection
    end
  end
end

module ChefIO
  class Dir
    class << self
      def method_missing(m, *args, &block)
        debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
        Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
        ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

        backend = Chef::Config.target_mode? ? Train::Dir : ::Dir
        backend.send(m, *args, &block)
      end
    end
  end

  class Etc
    class << self
      def method_missing(m, *args, &block)
        debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
        Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
        ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

        if ChefConfig::Config.target_mode? && !Chef::Client.transport_connection.os.unix?
          raise 'Etc support only on Unix, this is ' + Chef::Client.transport_connection.platform.title
        end

        backend = Chef::Config.target_mode? ? Train::Etc : ::Etc
        backend.send(m, *args, &block)
      end
    end
  end

  class File
    class << self
      def method_missing(m, *args, &block)
        debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
        Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
        ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

        backend = Chef::Config.target_mode? ? Train::File : ::File
        backend.send(m, *args, &block)
      end
    end
  end

  class FileUtils
    class << self
      def method_missing(m, *args, &block)
        debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
        Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
        ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

        backend = Chef::Config.target_mode? ? Train::FileUtils : ::FileUtils
        backend.send(m, *args, &block)
      end
    end
  end

  class Shadow
    class Passwd
      class << self
        def method_missing(m, *args, &block)
          debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
    	    Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
          ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

          backend = Chef::Config.target_mode? ? Train::Shadow::Passwd : ::Shadow::Passwd
          backend.send(m, *args, &block)
        end
      end
    end
  end

  class Tempfile
    class << self
      def method_missing(m, *args, &block)
        debug_message = format("%s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
        Chef::Log.debug format('%s::%s(%s)', self.to_s, m.to_s, args.join(', '))
        ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

        backend = Chef::Config.target_mode? ? Train::Tempfile : ::Tempfile
        backend.send(m, *args, &block)
      end
    end
  end

  # 67/68 done (~99%)
  module Train

    # 10/11 done
    class Dir
      # done (io): delete, home, mkdir, unlink, glob, entries, mktmpdir
      # done (non-io): tmpdir
      #
      # miss (ctx): chdir
      # oos: pwd
      class << self
        def delete(string)
          ::ChefIO::Train::FileUtils.rm_rf(string)
        end

        def entries(dirname)
          result = run_command("ls -a1 #{dirname}")
          result.stdout.lines
        rescue StandardError => e
          raise SystemCallError, e.message
        end

        def glob(pattern, flags)
          parts = pattern.split('/')

          longest_prefix = ""
          parts.each do |part|
            longest_prefix += "#{part}/" unless part.delete("[*?") != part
          end

          result = run_command("find #{longest_prefix}")
          result.stdout.lines.select { |path| ::ChefIO::Train::File.fnmatch(pattern, path, flags) }
        end

        # Transient Train != Persistent FS
        def chdir(dir)
          # Used in:
          # - archive_file
          # - dsc_script (OOS)
        end

        # Transient Train != Persistent FS
        def pwd
          # Used in:
          # - dsc_resource (OOS)
        end

        def home
          ::ChefIO::Train::Etc::getpwnam(Etc::getlogin).dir
        end

        def mkdir(string, mode = nil)
          ::ChefIO::Train::FileUtils.mkdir_p(string)
          ::ChefIO::Train::FileUtils.chmod(string, mode) if mode
        end

        def mktmpdir(prefix_suffix=nil)
          path = ::ChefIO::Train::Tempfile::Tmpname.create(prefix_suffix || "d")
          ::ChefIO::Dir::mkdir(path, 0700)

          path
        end

        # TODO
        # https://github.com/ruby/tmpdir/blob/master/lib/tmpdir.rb#L21
        def tmpdir
          if Chef::Client.transport_connection.os.windows?
            'C:\Windows\Temp'
          else
            '/tmp'
          end
        end

        def unlink(string)
          ::ChefIO::Train::FileUtils.rmdir(string)
        end

        private

        def run_command(cmd)
          Chef::Client.transport_connection.run_command(cmd)
        end
      end
    end

    # 5/5 done
    class Etc
      # done (io): getgrgid, getgrname, getlogin, getpwnam, getpwuid
      #
      # miss: -
      class << self
        def getgrgid(group_id)
          group.detect { |entry| entry.gid == group_id }
        end

        def getgrnam(name)
          group.detect { |entry| entry.name == name }
        end

        def getlogin
          @@login ||= Chef::Client.transport_connection.run_command('id -nu')
        end

        def getpwnam(name)
          passwd.detect { |entry| entry.name == name }
        end

        def getpwuid(uid)
          passwd.detect { |entry| entry.uid == uid }
        end

        private

        def passwd
          @@passwd ||= []
          return @@passwd unless @@passwd.empty?

          File::readlines('/etc/passwd').lines.each do |line|
            name, passwd, uid, gid, gecos, dir, shell = line.split(':')

            @@passwd << ::Etc::Passwd.new(name, passwd, uid, gid, gecos, dir, shell)
          end

          @@passwd
        end

        def group
          @@group ||= []
          return @@group unless @@group.empty?

          File::readlines('/etc/passwd').lines.each do |line|
            name, passwd, gid, mem = line.split(':')

            @@group << ::Etc::Group.new(name, passwd, gid, mem.split(','))
          end

          @@group
        end
      end
    end

    # 40/40 done
    class File
      # done (io): exist?, read, readlines, open, file?, directory?, mtime, size, delete, binread, symlink?, blockdev?, chardev?, pipe?, socket?, file?, chown, chmod, stat, lstat, utime, foreach, realpath, absolute_path
      # done (non-io): expand_path, join, basename, dirname, split, basename, extname, fnmatch, SEPARATOR, lchmod
      # done (context): executable?, readable?, writable?
      #
      # miss: -
      class << self
        # TODO: new

        @@files = {}

        def SEPARATOR
          Chef::Client.transport_connection.platform.windows? ? "\\" : '/'
        end

        def binread(name, length = nil, offset = 0)
          content = readlines(file_name)
          length = content.size - offset if length.nil?

          content[offset, length]
        end

        def chmod(mode_int, filename)
          ::ChefIO::Train::FileUtils.chmod(mode, string, mode)
        end

        def chown(owner_int, group_int, file_name)
          ::ChefIO::Train::FileUtils.chown(user, group, [file_name])
        end

        def delete(file_name)
          cmd = format('rm %<file>s', file_name)
          Chef::Client.transport_connection.run_command(cmd)
        end

        def exists?(file_name)
          exist?(file_name)
        end

        # TODO: ~ and relative expansion -> Cptn. Context
        # almost exclusively used with absolute __dir__ or __FILE__ though
        def expand_path(file_name, dir_string = "")
          # Chef::Util::PathHelper.join ?

          require 'pathname' unless defined?(Pathname)

          # Will just collapse relative paths inside
          pn = Pathname.new File.join(dir_string, file_name)
          clean = pn.cleanpath
        end

        def foreach(name)
          return unless block_given?

          readlines(name).each { |line| yield line }
        end

        def lchmod(_mode_int, _file_name)
          # Not available
        end

        # Needs to hook into io.close (Closure?)
        def new(filename, mode = "r")
          raise NotImplementedError, 'ChefIO::Train::File.new is still TODO'
        end

        # TODO: non-block && mode != 'r'
        def open(file_name, mode = "r")
          # Would need to hook into io.close (Closure?)
          raise 'Hell' if mode != 'r' && !block_given?

          content = readlines(file_name)
          new_content = content.dup

          io = StringIO.new(new_content)

          if mode.start_with? 'w'
            io.truncate(0)
          elsif mode.start_with? 'a'
            io.seek(0, IO::SEEK_END)
          end

          if block_given?
            yield(io)

            if (content != new_content) && !mode.start_with?('r')
              Chef::Client.transport_connection.file(file_name).content = new_content # Need Train 2.5+
              @@files[file_name] = new_content
            end
          end

          io
        end

        def readable?(file_name)
          cmd = "sudo -u ubuntu test -r #{file_name}; echo $?"
          result = Chef::Client.transport_connection.run_command(cmd)

          result.exit_status == 0
        end

        def readlines(file_name)
          @@files[file_name] ||= Chef::Client.transport_connection.file(file_name).content
        end

        def realpath(pathname)
          result = Chef::Client.transport_connection.run_command("realpath #{pathname}")
          result.stdout.chomp
        end
        alias_method :absolute_path, :realpath

        ### START Could be in Train::File::...

        def executable?(file_name)
          cmd = "sudo -u ubuntu test -r #{file_name}; echo $?"
          result = Chef::Client.transport_connection.run_command(cmd)

          result.exit_status == 0
        end

        # def ftype(file_name)
        #   case type(file_name)
        #   when :block_device
        #     "blockSpecial"
        #   when :character_device
        #     "characterSpecial"
        #   when :symlink
        #     "link"
        #   else
        #     type(file_name).to_s
        #   end
        # end

        def link(old_name, new_name)
          ::ChefIO::Train::FileUtils.ln(old_name, new_name)
        end

        def readlink(file_name)
          raise Errno::EINVAL unless symlink?(file_name)

          result = Chef::Client.transport_connection.run_command("reallink #{file_name}")
          result.stdout.chomp
        end

        # def setgid?(file_name)
        #   mode(file_name) & 04000 != 0
        # end

        # def setuid?(file_name)
        #   mode(file_name) & 02000 != 0
        # end

        # def sticky?(file_name)
        #   mode(file_name) & 01000 != 0
        # end

        # def size?(file_name)
        #   exist?(file_name) && size(file_name) > 0
        # end

        PseudoStat = Struct.new(:uid, :gid, :mode)
        def stat(file_name)
          stat = Chef::Client.transport_connection.file(file_name).stat

          PseudoStat.new(stat[:uid], stat[:gid], stat[:mode])
        end
        alias_method :lstat, :stat

        def symlink(old_name, new_name)
          ::ChefIO::Train::FileUtils.ln_s(old_name, new_name)
        end

        def utime(atime, mtime, file_name)
          atime_fmt = atime.strftime('%Y%m%d%H%M.%S')
          mtime_fmt = mtime.strftime('%Y%m%d%H%M.%S')

          run_command("touch #{file_name} -a -t #{atime_fmt}; touch #{file_name} -m -t #{timmtime_fmtestamp}")
        end

        def unlink(*list)
          ::ChefIO::Train::FileUtils.rm(list, force: nil, noop: nil, verbose: nil)
        end

        def writable?(file_name)
          cmd = "sudo -u ubuntu test -w #{file_name}; echo $?"
          result = Chef::Client.transport_connection.run_command(cmd)

          result.exit_status == 0
        end

        # def world_readable?(file_name)
        #   mode(file_name) & 0001 != 0
        # end

        # def world_writable?(file_name)
        #   mode(file_name) & 0002 != 0
        # end

        # def zero?(file_name)
        #   exists?(file_name) && size(file_name) == 0
        # end

        ### END: Could be in Train

        # passthrough to Train Connection/file
        def method_missing(m, *args, &block)
          nonio    = %i[extname join dirname path split fnmatch basename]

          passthru = %i[directory? exist? exists? file? mtime pipe? size socket? symlink?] # gid uid
          redirect = {
            blockdev?: :block_device?,
            chardev?: :character_device?
          }
          filestat = %i[mtime] #mode

          # In Train but not File/File::Stat:
          # group link_path linked_to? mode? owner selinux_label shallow_link_path type grouped_into? mounted sanitize_filename unix_mode_mask

          if nonio.include? m
            ::File.send(m, *args) # block?

          elsif passthru.include? m
            Chef::Log.debug 'File::' + m.to_s + ' passed to Train.file.' + m.to_s

            file_name, other_args = args[0], args[1..]

            file = Chef::Client.transport_connection.file(file_name)
            file.send(m, *other_args) # block?

          elsif filestat.include? m
            Chef::Log.debug 'File::' + m.to_s + ' passed to Train.file.stat.' + m.to_s

            Chef::Client.transport_connection.file(args[0]).stat[m]

          elsif redirect.key?(m)
            Chef::Log.debug 'File::' + m.to_s + ' redirected to Train.file.' + redirect[m].to_s

            file_name, other_args = args[0], args[1..]

            file = Chef::Client.transport_connection.file(file_name)
            file.send(redirect[m], *other_args) # block?

          else
            debug_message = format("Unsupported method %s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
            ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

            raise debug_message
          end
        end

        private

        def run_command(cmd)
          Chef::Client.transport_connection.run_command(cmd)
        end
      end
    end

    # 10/10 done
    class FileUtils
      # done (io): cp, rm, mkdir_p, chown, remove_entry, rm_rf, mv, rm_r, chmod, touch
      #
      # miss: -
      class << self
        # (All commands are copied 1:1 from FileUtils source)
        def chmod(mode, list, noop: nil, verbose: nil)
          cmd = sprintf('chmod %s %s', __mode_to_s(mode), list.join(' '))

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def chmod_R(mode, list, noop: nil, verbose: nil, force: nil)
          cmd = sprintf('chmod -R%s %s %s', (force ? 'f' : ''), mode_to_s(mode), list.join(' '))

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def chown(user, group, list, noop: nil, verbose: nil)
          cmd = sprintf('chown %s %s', (group ? "#{user}:#{group}" : user || ':'), list.join(' '))

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def chown_R(user, group, list, noop: nil, verbose: nil, force: nil)
          cmd = sprintf('chown -R%s %s %s', (force ? 'f' : ''), (group ? "#{user}:#{group}" : user || ':'), list.join(' '))

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        # cmp
        # collect_method
        # commands
        # compare_file
        # compare_stream

        def cp(src, dest, preserve: nil, noop: nil, verbose: nil)
          cmd = "cp#{preserve ? ' -p' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end
        alias_method :copy, :cp

        def cp_lr(src, dest, noop: nil, verbose: nil, dereference_root: true, remove_destination: false)
          cmd = "cp -lr#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def cp_r(src, dest, preserve: nil, noop: nil, verbose: nil, dereference_root: true, remove_destination: nil)
          cmd = "cp -r#{preserve ? 'p' : ''}#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        # getwd (alias pwd)
        # have_option?
        # identical? (alias compare_file)

        def install(src, dest, mode: nil, owner: nil, group: nil, preserve: nil, noop: nil, verbose: nil)
          cmd = "install -c"
          cmd << ' -p' if preserve
          cmd << ' -m ' << mode_to_s(mode) if mode
          cmd << " -o #{owner}" if owner
          cmd << " -g #{group}" if group
          cmd << ' ' << [src, dest].flatten.join(' ')

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def ln(src, dest, force: nil, noop: nil, verbose: nil)
          cmd = "ln#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end
        alias_method :link, :ln

        def ln_s(src, dest, force: nil, noop: nil, verbose: nil)
          cmd = "ln -s#{force ? 'f' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end
        alias_method :symlink, :ln_s

        def ln_sf(src, dest, noop: nil, verbose: nil)
          ln_s(src, dest, force: true, noop: noop, verbose: verbose)
        end

        def mkdir(list, mode: nil, noop: nil, verbose: nil)
          cmd = "mkdir #{mode ? ('-m %03o ' % mode) : ''}#{list.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def mkdir_p(list, mode: nil, noop: nil, verbose: nil)
          cmd = "mkdir -p #{mode ? ('-m %03o ' % mode) : ''}#{Array(list).join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end
        alias_method :makedirs, :mkdir_p
        alias_method :mkpath, :mkdir_p

        def mv(src, dest, force: nil, noop: nil, verbose: nil, secure: nil)
          cmd = "mv#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        # options
        # options_of
        # pwd
        # remove
        # remove_entry_secure
        # remove_file

        def rmdir(list, parents: nil, noop: nil, verbose: nil)
          return if noop

          __run_command
        end

        def rm(list, force: nil, noop: nil, verbose: nil)
          cmd = "rm#{force ? ' -f' : ''} #{list.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def rm_f(list, force: nil, noop: nil, verbose: nil, secure: nil)
          rm(list, force: true, noop: noop, verbose: verbose)
        end

        def rm_r(list, force: nil, noop: nil, verbose: nil, secure: nil)
          cmd = "rm -r#{force ? 'f' : ''} #{list.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def rm_rf(list, noop: nil, verbose: nil, secure: nil)
          rm_r(list, force: true, noop: noop, verbose: verbose, secure: secure)
        end
        alias_method :remove_entry, :rm_rf
        alias_method :rmtree, :rm_rf
        alias_method :safe_unlink, :rm_rf

        def rmdir(list, parents: nil, noop: nil, verbose: nil)
          cmd = "rmdir #{parents ? '-p ' : ''}#{list.join ' '}"

          $logger.debug cmd if verbose
          return if noop

          __run_command(cmd)
        end

        def touch(list, noop: nil, verbose: nil, mtime: nil, nocreate: nil)
          return if noop

          __run_command "touch #{nocreate ? '-c ' : ''}#{t ? t.strftime('-t %Y%m%d%H%M.%S ') : ''}#{list.join ' '}"
        end

        # uptodate?

        def method_missing(m, *args, &block)
          debug_message = format("Unsupported method %s::%s(%s) in %s\n", self.to_s, m.to_s, args.join(', '), binding.callers.at(1).source_location.join(':'))
          ::File.open("/tmp/cheftm-#{$$}.log", "a") { |fp| fp.write debug_message }

          raise debug_message
        end

        private

        # TODO: Symbolic modes
        def __mode_to_s(mode)
          mode.to_s(8)
        end

        def __run_command(cmd)
          Chef::Client.transport_connection.run_command(cmd)
        end
      end
    end

    # 0/1 done
    class Shadow
      module Passwd
        class << self
          def getspnam(name)
            shadow.detect { |entry| entry.name == name }
          end

          private


          ShadowEntry = Struct.new(:name, :pwd, :lstchg, :min, :max, :warn, :inact, :expire, :loginclass)

          def shadow
            @@shadow ||= []
            return @@shadow unless @@shadow.empty?

            File::readlines('/etc/shadod').lines.each do |line|
              name, pwd, lstchg, min, max, warn, inact, expire, loginclass = line.split(':')

              @@shadow << ShadowEntry.new(name, pwd, lstchg, min, max, warn, inact, expire, loginclass)
            end

            @@shadow
          end
        end
      end
    end

    # 2/2 done
    class Tempfile
      module Tmpname
        def create(basename="", tmpdir=nil, _mode: 0, **_options)
          tmpdir = ::ChefIO::Train::Dir.tmpdir unless tmpdir

          name = format("%<prefix>s%<time>s-%<process_id>s-%<random>s%",
                       prefix: basename,
                       time: Time.now.strftime("%Y%m%d"),
                       process_id: Process.pid,
                       random: rand(36**6).to_s(36))

          File.join(tmpdir, path)
        end
      end

      attr_reader :path

      def initialize(basename="", tmpdir=nil, mode: 0, **options)
        @path = Tmpname.create(basename, tmpdir, **options)
      end

      # Defer everything but name generation to File
      # TODO: Boom
      def open
require'pry';binding.pry
        ::ChefIO::Train::File.open(path, mode = "w", &block)
      end
    end
  end
end

# Scope: Unix only (due to Windows use of Registry/FFI/...)
#        130 Resources => 90 Unix
#        Problematic: archive_file (Dir.chdir + File operations with relative paths)

# puts "  " + ChefIO::File.dirname('/etc/passwd').to_s
# puts "  " + ChefIO::File.exist?('/etc/passwd').to_s
# puts "  " + ChefIO::File.blockdev?('/etc/passwd').to_s
# puts "  " + ChefIO::File.executable?('/bin/bash').to_s
# puts "  " + ChefIO::File.size('/bin/bash').to_s
# puts "  " + ChefIO::File.readlines('/etc/passwd').to_s
# #ChefIO::File.open("/tmp/xyz2", "w") { |f| f.write '.' }
# require'pry';binding.pry
# puts
