require 'heroku_san/railtie.rb' if defined?(Rails) && Rails::VERSION::MAJOR == 3
require 'heroku_san/git'

class HerokuSan
  attr_reader :app_settings, :config_file
  class NoApps < StandardError; end

  include Git
    
  def initialize(config_file)
    @apps = []
    @config_file = config_file

    @app_settings = parse_yaml(config_file)
    
    # support heroku_san format
    if @app_settings.has_key? 'apps'
      @app_settings = @app_settings['apps']
      @app_settings.each_pair do |stage, app_name|
        @app_settings[stage] = {'app' => app_name}
      end
    end
    
    # load external config
    if (config_repo = @app_settings.delete('config_repo'))
      require 'tmpdir'
      tmp_config_dir = Dir.mktmpdir
      tmp_config_file = File.join tmp_config_dir, 'config.yml'
      git_clone(config_repo, tmp_config_dir)
      extra_config = parse_yaml(tmp_config_file)
    else
      extra_config = {}
    end
    
    # make sure each app has a 'config' section & merge w/extra
    @app_settings.keys.each do |name|
      @app_settings[name]['config'] ||= {}
      @app_settings[name]['config'].merge!(extra_config[name]) if extra_config[name]
    end    
  end

  def all
    @app_settings.keys
  end
  
  def <<(*app)
    app.flatten.each do |a|
      @apps << a if all.include?(a)
    end
    self
  end
  
  def apps
    if !@apps.empty?
      @apps
    else
      case all.size
      when 1
        $stdout.puts "Defaulting to #{all.first.inspect} since only one app is defined"
        all
      else
        active_branch = self.git_active_branch
        all.select do |app| 
          app == active_branch and ($stdout.puts("Defaulting to #{app.inspect} as it matches the current branch") || true)
        end
      end
    end
  end
  
  def each_app
    raise NoApps if apps.empty?
    apps.each do |name|
      app = @app_settings[name]['app']
      yield(name, app, "git@heroku.com:#{app}.git", @app_settings[name]['config'])
    end
  end
  
  def migrate(app)
    sh "heroku rake db:migrate --app #{app}"
    sh "heroku restart --app #{app}"
  end
  
  def maintenance(app, action)
    sh "heroku maintenance:#{action} --app #{app}"
  end
  
  def create_config
    template = File.join(File.dirname(__FILE__), 'templates', 'heroku.example.yml')
    if File.exists?(@config_file)
      false
    else
      FileUtils.cp(template, @config_file)
      true
    end
  end
  
private
  
  def parse_yaml(config_file)
    if File.exists?(config_file)
      if defined?(ERB)
        YAML.load(ERB.new(File.read(config_file)).result)
      else
        YAML.load_file(config_file)
      end
    else
      {}
    end
  end
end