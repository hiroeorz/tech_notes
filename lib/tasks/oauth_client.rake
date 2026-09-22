namespace :oauth do
  namespace :client do
    desc "Create a confidential Doorkeeper OAuth client and print uid/secret (e.g. bin/rails oauth:client:create[Gemini,https://client.example.com/callback])"
    task :create, [ :name, :redirect_uri ] => :environment do |_task, args|
      name = args[:name].to_s.strip
      redirect_uri = args[:redirect_uri].to_s.strip

      if name.blank? || redirect_uri.blank?
        abort "Usage: bin/rails oauth:client:create[NAME,REDIRECT_URI]"
      end

      if Doorkeeper::Application.exists?(name: name)
        abort "OAuth client #{name.inspect} already exists. Use oauth:client:show to display it."
      end

      app = Doorkeeper::Application.create!(
        name: name,
        redirect_uri: redirect_uri,
        scopes: "read write",
        confidential: true
      )

      puts "uid: #{app.uid}"
      puts "secret: #{app.secret}"
    rescue ActiveRecord::RecordInvalid => e
      abort "Failed to create OAuth client: #{e.message}"
    end

    desc "Show uid/secret of an existing Doorkeeper OAuth client (e.g. bin/rails oauth:client:show[Gemini])"
    task :show, [ :name ] => :environment do |_task, args|
      name = args[:name].to_s.strip

      abort "Usage: bin/rails oauth:client:show[NAME]" if name.blank?

      app = Doorkeeper::Application.find_by(name: name)
      abort "OAuth client #{name.inspect} not found." if app.nil?

      puts "uid: #{app.uid}"
      puts "secret: #{app.secret}"
    end
  end
end
