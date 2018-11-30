# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update destroy]

  # GET /users
  # GET /users.json
  def index
    @users = User.all
  end

  # GET /users/1
  # GET /users/1.json
  def show
    respond_to do |format|
      format.html { render }
      format.zip do
        files = save_files_on_server @user.pictures
        zip_data = create_temporary_zip_file files

        send_data(zip_data, type: 'application/zip', filename: 'user.zip')
      end
    end
  end

  # GET /users/new
  def new
    @user = User.new
  end

  # GET /users/1/edit
  def edit; end

  # POST /users
  # POST /users.json
  def create
    @user = User.new(user_params)

    respond_to do |format|
      if @user.save
        format.html { redirect_to @user, notice: 'User was successfully created.' }
        format.json { render :show, status: :created, location: @user }
      else
        format.html { render :new }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /users/1
  # PATCH/PUT /users/1.json
  def update
    respond_to do |format|
      if @user.update(user_params)
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1
  # DELETE /users/1.json
  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_to users_url, notice: 'User was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Download active storage files on server in a temporary folder
  #
  # @param files [ActiveStorage::Attached::Many] files to save
  # @return [Array<String>] files paths of saved files
  def save_files_on_server(files)
    # get a temporary folder and create it
    temp_folder = File.join(Dir.tmpdir, 'user')
    FileUtils.mkdir_p(temp_folder) unless Dir.exist?(temp_folder)

    # download all ActiveStorage into
    files.map do |picture|
      filename = picture.filename.to_s
      filepath = File.join temp_folder, filename
      File.open(filepath, 'wb') { |f| f.write(picture.download) }
      filepath
    end
  end

  # Create a temporary zip file & return the content as bytes
  #
  # @param filepaths [Array<String>] files paths
  # @return [String] as content of zip
  def create_temporary_zip_file(filepaths)
    require 'zip'
    temp_file = Tempfile.new('user.zip')

    begin
      # Initialize the temp file as a zip file
      Zip::OutputStream.open(temp_file) { |zos| }

      # open the zip
      Zip::File.open(temp_file.path, Zip::File::CREATE) do |zip|
        filepaths.each do |filepath|
          filename = File.basename filepath
          # add file into the zip
          zip.add filename, filepath
        end
      end

      return File.read(temp_file.path)
    ensure
      # close all ressources & remove temporary files
      temp_file.close
      temp_file.unlink
      filepaths.each { |filepath| FileUtils.rm(filepath) }
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def user_params
    params.require(:user).permit(:name, pictures: [])
  end
end
