class BuildingController < ConsoleController

  def show
    @domain = Domain.find :one, :as => session_user
    @application = @domain.find_application params[:application_id]
    redirect_to new_application_building_path(@application) unless @application.builds?
  end

  def new
    @domain = Domain.find :one, :as => session_user
    apps = @domain.applications
    @application = apps.find{ |a| a.name == params[:application_id] } or raise ActiveResource::ResourceNotFound, params[:application_id]
    @jenkins_server = apps.find{ |a| a.jenkins_server? } || Application.new(:name => 'jenkins', :cartridge => 'jenkins-1.4', :domain => @domain)
    @cartridge_type = CartridgeType.cached.find 'jenkins-client-1.4', :as => session_user
    @cartridge = Cartridge.new :name => @cartridge_type.name
  end

  def create
    @domain = Domain.find :one, :as => session_user
    apps = @domain.applications
    @application = apps.find{ |a| a.name == params[:application_id] } or raise ActiveResource::ResourceNotFound, params[:application_id]
    @jenkins_server = apps.find{ |a| a.jenkins_server? }
    @cartridge_type = CartridgeType.cached.find 'jenkins-client-1.4', :as => session_user
    @cartridge = Cartridge.new :name => @cartridge_type.name

    unless @jenkins_server
      @jenkins_server = Application.new(
        :name => params[:application][:name],
        :cartridge => 'jenkins-1.4',
        :domain => @domain,
        :as => session_user)

      if @jenkins_server.save
        message = @jenkins_server.remote_results
      else
        render :new and return
      end
    end

    @cartridge.application = @application

    success = false

    6.times do
      success = @cartridge.save

      break unless !success && @cartridge.has_exit_code?(157, :on => :cartridge)
      logger.debug "  Jenkins server could not be contacted, sleep and then retry\n    #{@cartridge.errors.inspect}"
      sleep(10)
    end

    if success
      redirect_to application_building_path(@application), :flash => {:info_pre => @cartridge.remote_results.concat(message || []).concat(['Your application is now building with Jenkins.'])}
    else
      @cartridge.errors.full_messages.each{ |m| @jenkins_server.errors.add(:base, m) }
      flash.now[:info_pre] = message
      render :new
    end
  end

  def delete
    @domain = Domain.find :one, :as => session_user
    @application = @domain.find_application params[:application_id]
    redirect_to new_application_building_path(@application) unless @application.builds?
  end

  def destroy
    @domain = Domain.find :one, :as => session_user
    @application = @domain.find_application params[:application_id]
    if @application.destroy_build_cartridge
      redirect_to application_path(@application), :flash => {:success => "#{@application.name} is no longer building through Jenkins."}
    else
      render :delete
    end
  end
end
