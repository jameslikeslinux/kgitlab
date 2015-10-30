require 'kgitlab'
require 'thor'

# A simple command-line interface for Kgitlab built with Thor.
#
# @see http://whatisthor.com/ Thor Homepage
# @author James T. Lee <jtl@umd.edu>
class Kgitlab::CLI < Thor
  desc 'server', 'Run a GitLab system hook receiver'
  option :config, :type => :string, :desc => 'Path to Kgitlab\'s YAML configuration', :required => true
  def server
    Kgitlab.new(options['config']).server
  end

  desc 'exec-shell', 'Execute the GitLab shell based on Kerberos identity'
  def exec_shell
    Kgitlab::exec_shell
  end
end
