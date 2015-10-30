require 'webrick'
require 'yaml'
require 'json'
require 'gitlab'

# This class implements a basic web server that responds to GitLab
# system hooks to create dummy SSH keys for new users and maps them
# to kerberos principals so that users can manage their repositories
# via SSH using kerberos authentication.
#
# @author James T. Lee <jtl@umd.edu>
class Kgitlab
  # If the user who runs this function has logged in with kerberos and
  # the user has a dummy key created by this application, then execute
  # the GitLab shell.
  #
  # This is meant to be performed in the git user's shell profile.
  def self.exec_shell
    principal = $1 if `klist` =~ /[Pp]rincipal: (.+)/
    if principal
      File.open("#{ENV['HOME']}/.k5keys") do |file|
        key = $1 if file.read =~ /^#{principal} (key-\d+)$/
        if key
          exec "/opt/gitlab/embedded/service/gitlab-shell/bin/gitlab-shell #{key}"
        end
      end
    end
  end

  # @param config_file [String] the path to a YAML configuration file
  def initialize(config_file)
    @options = YAML.load_file(config_file)
    @home = Etc.getpwnam(@options['git_user']).dir
    @k5login = "#{@home}/.k5login"
    @k5keys = "#{@home}/.k5keys"

    # Configure the GitLab client API for adding a dummy key to a user
    Gitlab.endpoint = @options['api_url']
    Gitlab.private_token = @options['api_token']
  end

  # Start a basic WEBrick web server to respond to GitLab system hooks
  # and run until interrupted.  Any exceptions in the request handling
  # are logged and the WEBrick server moves on to the next request, so
  # we don't do too much error handling.  This stuff is simple enough
  # anyway.
  #
  # WEBrick is also single threaded, which, keeps the code complexity
  # down (we don't need to worry about concurrent access to files while
  # handling requests).
  def server
    server = WEBrick::HTTPServer.new(:BindAddress => '0.0.0.0', :Port => @options['port'])
    server.mount_proc '/' do |req, res|
      handle_request(req.body) if req.body
    end
    trap 'INT' do server.shutdown end
    server.start
  end

  private

  # Switch based on system hook invoked
  #
  # @param payload_json [String] the JSON body provided by the GitLab server
  def handle_request(payload_json)
    payload = JSON.parse(payload_json)

    case payload['event_name']
      when 'user_create'
        handle_user_create(payload)
      when 'key_create'
        handle_key_create(payload)
      when 'key_destroy'
        handle_key_destroy(payload)
      else
        # ignore the request
    end
  end

  # When a new user is created, give them a dummy SSH key.
  # (The SSH key is real, but the private key is thrown away
  # immediately.)
  #
  # @param payload [Hash{:key => String, :value => Object}]
  #   the data associated with a user_create event
  # @see https://github.com/gitlabhq/gitlabhq/blob/master/doc/system_hooks/system_hooks.md System Hooks
  def handle_user_create(payload)
    Gitlab.post("/users/#{payload['user_id']}/keys", :body => {:title => 'Kerberos', :key => generate_ssh_public_key})
  end

  # When a new key is created with a title of 'Kerberos', associate it
  # with the users kerberos principal by adding them to a file called
  # .k5keys, and add the kerberos principal to the git user's .k5login
  # file.
  #
  # @param payload [Hash{:key => String, :value => Object}]
  #   the data associated with a key_create event
  # @see https://github.com/gitlabhq/gitlabhq/blob/master/doc/system_hooks/system_hooks.md System Hooks
  def handle_key_create(payload)
    if payload['key'] =~ /Kerberos$/
      File.open(@k5keys, 'a') do |file|
        file.puts "#{payload['username']}@#{@options['realm']} key-#{payload['id']}"
      end

      File.open(@k5login, 'a') do |file|
        file.puts "#{payload['username']}@#{@options['realm']}"
      end
    end
  end

  # When a user is deleted, their keys are deleted first, and system
  # hooks are triggered for those actions.  When received, simply
  # remove the associated user from the k5 files.
  #
  # @param payload [Hash{:key => String, :value => Object}]
  #   the data associated with a key_destroy event
  # @see https://github.com/gitlabhq/gitlabhq/blob/master/doc/system_hooks/system_hooks.md System Hooks
  def handle_key_destroy(payload)
    if payload['key'] =~ /Kerberos$/
      # This is admittedly not very pretty, but I want to, in some
      # semi-atomic way delete the user from the k5 files.  The most
      # obvious choice is to write to a new file and move it over the
      # existing files, but I don't know what that would do to the
      # labels.
      system("sed -i '/^#{payload['username']}@#{@options['realm']}/d' '#{@k5login}'")
      system("sed -i '/^#{payload['username']}@#{@options['realm']}/d' '#{@k5keys}'")
    end
  end

  # Generate a "dummy" SSH key.  Quick and dirty, but it works.  We
  # can't just give GitLab any old string because it checks that it
  # is a valid SSH key.
  #
  # @return [String] the SSH public key
  def generate_ssh_public_key
    private_key_file = Dir::Tmpname.make_tmpname("/tmp/kgitlab", nil)
    system("ssh-keygen -t rsa -f #{private_key_file} -N '' -C Kerberos")
    public_key = File.read("#{private_key_file}.pub")
    File.unlink(private_key_file)
    File.unlink("#{private_key_file}.pub")
    public_key
  end
end
