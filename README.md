# Créer une archive avec Rails et ActiveStorage

Récemment, pour mon projet [isignif.fr](https://isignif.fr), j'ai voulu implémenter une fonctionnalité qui permet de **télécharger une archive** de plusieurs fichiers `.zip`. Rien de bien compliqué sauf que j'utilise [**ActiveStorage**][active_storage_guide]. Active Storage est fait partit des des nouvelles fonctionnalité de Rails 5.2 (sortit janvier 2018) qui permet d'**attacher** un fichier à un modèle en utilisant **divers services de stockage** tels que Amazon S3, Google Cloud Storage, or Microsoft Azure Storage.

Cela présente beaucoup d'avantage car les fichiers sont **séparés** du serveur web. Ils sont stockés sur des services qui sont **spécialisés** dans le stockage des fichiers. Le problème est que, lorsqu'on veut les manipuler, ils ne sont pas présent physiquement sur le serveur web.

Vu que la documentation est assez pauvre la dessus (puisque c'est une fonctionnalité récente), j'ai décidé d'écrire un article.

Dans cet article nous allons:

- rédiger des tests qui correspondent au fonctionnement attendu
- implémenter le code pour passer les tests
- factoriser et améliorer l'implémentation
- exporter le tout dans une librairie

**TLDR**: Passé la complexité de l'implémentation du code, il est très facile de déplacer le code dans des méthodes réutilisable en utilisant les [`ActiveSupport::Concern`][concerns_api].

## Sommaire

* TOC
{:toc}

## Création d'un exemple

### Génération du projet

Pour ce tutoriel j'ai choisis de partir d'un nouveau projet. Créons donc un nouveau projet Rails:

~~~bash
$ rails new zip_example --skip-action-cable --skip-coffee --skip-turbolinks --skip-system-test --skip-action-mailer
~~~

> j'ai ajouté "quelques" *flags* `--skip` afin d'enlever tout ce qui nous sera inutile

On va aussi générer aussi une entité `User` avec la commande `scaffold`:

~~~bash
$ rails g scaffold user name:string
~~~

> La commande `scaffold` va s'occuper de créer le *controller*, le *model*, les *views* et même la migrations

Maintenant puisque je veux utiliser *Active Storage*, j'ai besoin de l'**installer**. C'est très facile, la commande suivante le fait pour nous:

~~~bash
$ rails active_storage:install
~~~

> Cette commande génère juste une migration qui va créer les tables `active_storage_blobs` & `active_storage_attachments`

Maintenant que toutes nos **migrations** sont crées, il suffit de les jouer:

~~~bash
$ rake db:migrate
~~~

Voilà, nous somme prêt à coder!

### Ajout de l'Active Storage

Pour attacher un(des) fichier(s) à un modèles suffit d'ajouter **une seule ligne** à notre modèle `User`. C'est là toute la beauté de *conventions over configuration*!

~~~ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many_attached :pictures
end
~~~

> Chaque `ActFile` possède un fichier (`has_one_attached :file`) qui représente donc une liaison vers un objet [`ActiveStorage::Attached::Many`][active_storage_attached_many].

Je vais aussi ajouter un champ `file_field :pictures` au **formulaire** pour qu'on puisse charger nos fichiers

~~~erb
<!-- app/views/users/_form.html.erb -->
<%= form_with(model: user, local: true) do |form| %>
  <!-- ... -->
  <%= form.label :name %>
  <%= form.text_field :name %>
  <%= form.file_field :pictures, multiple: true, class: 'form-control' %>
  <%= form.submit %>
<% end %>
~~~

On n'oublie pas d'**autoriser** ce champs dans le *controller*:

~~~ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  # ....

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end
end
~~~


On démarre maintenant le serveur avec `rails server` et se rend à l'URL `http://localhost:3000/users/new` pour créer un utilisateur:

![Formulaire de création d'un utilisateur avec les fichiers](/img/blog/active_storage_create_user.png)

Lorsqu'on valide le formulaire avec des fichiers, on voit dans la console du serveur que les fichiers sont **chargés**:

~~~
Started POST "/users" for 127.0.0.1 at 2018-11-30 08:48:29 +0100
Processing by UsersController#create as HTML
  ActiveStorage::Blob Create (1.0ms)  INSERT INTO "active_storage_blobs" ("key", "filename", "content_type", "metadata", "byte_size", "checksum", "created_at") VALUES (?, ?, ?, ?, ?, ?, ?)  [["key", "2gVacD6hhv6viMW2bgYGVzsV"], ["filename", "2172652.png"], ["content_type", "image/png"], ["metadata", "{\"identified\":true}"], ["byte_size", 414730], ["checksum", "L2ka9VIXeONlrtvE8w0kMQ=="], ["created_at", "2018-11-30 07:48:29.724333"]]
  ActiveStorage::Blob Create (0.4ms)  INSERT INTO "active_storage_blobs" ("key", "filename", "content_type", "metadata", "byte_size", "checksum", "created_at") VALUES (?, ?, ?, ?, ?, ?, ?)  [["key", "z1JQEeVUx9Nbe7cndx5ZN1dh"], ["filename", "b64ae90.jpg"], ["content_type", "image/jpeg"], ["metadata", "{\"identified\":true}"], ["byte_size", 403558], ["checksum", "rBfrYgoJn0T5ZMsy4e9vSg=="], ["created_at", "2018-11-30 07:48:29.756230"]]
  ActiveStorage::Attachment Create (0.4ms)  INSERT INTO "active_storage_attachments" ("name", "record_type", "record_id", "blob_id", "created_at") VALUES (?, ?, ?, ?, ?)  [["name", "pictures"], ["record_type", "User"], ["record_id", 2], ["blob_id", 3], ["created_at", "2018-11-30 07:48:29.774326"]]
  ActiveStorage::Attachment Create (0.2ms)  INSERT INTO "active_storage_attachments" ("name", "record_type", "record_id", "blob_id", "created_at") VALUES (?, ?, ?, ?, ?)  [["name", "pictures"], ["record_type", "User"], ["record_id", 2], ["blob_id", 4], ["created_at", "2018-11-30 07:48:29.777281"]]
Completed 302 Found in 96ms (ActiveRecord: 37.5ms)
~~~



## Création du ZIP

L'idée serait donc de créer une route `http://localhost:3000/users/1.zip` qui nous permettrait d'obtenir une archive contenant tous les fichiers liés à l'utilisateur.

### Création du test

Comme toujours, on essaie de créer un test qui **échoue** dans un premier temps ([*Test Driven Development*][tdd]). J'ai simplement choisis de créer un *test controller* et de **tester la réponse** de la requête. C'est très simple, mais ça marche:

~~~ruby
# test/controllers/users_controller_test.rb
require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest

  # ...

  test 'should get user as zip' do
    get user_url(@user, format: :zip)
    assert_response :success
    assert_equal 'application/zip', response.content_type
  end
end
~~~

Pour l'instant, le test échoue et **c'est normal**:

~~~
$ rake test

# Running:

.......E

Error:
UsersControllerTest#test_should_get_user_as_zip:
ActionController::UnknownFormat: UsersController#show is missing a template for this request format and variant.

request.formats: ["application/zip"]
~~~

### Implémentation

Dans un premier temps, il est nécessaire de **télécharger** les fichiers sur le serveur. Pour cela, nous allons:

1. **Créer** un dossier temporaire
2. **Télécharger** le contenu des fichiers avec [`ActiveStorage::Blob#download`][active_storage_blob_download]
3. **Zipper** les fichier dans le dossier temporaire avec le contenu que je viens de récupérer
4. Renvoyer le contenu du fichier zip

Vu qu'on parle de zip, nous allons utiliser la gem [rubyzip][rubyzip]. On modifie donc le *Gemfile*:

~~~ruby
# Gemfile
gem 'rubyzip', '>= 1.0.0'
~~~

On installe avec `bundle install` et on démarre le serveur avec `rails s`. On est prêt à coder!

Comme je le disais plus haut, le problème est qu'il faut **récupérer** les fichiers sur le serveur. On aurais pu choisir de mettre le contenu du fichier en mémoire vive mais nous ne connaissons pas la tailles des fichiers donc je préfère les stocker temporairement sur le disque dur.

~~~ruby
# app/controllers/users_controller.rb

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
~~~

Maintenant que les fichiers sont sur le disque dur, nous pouvons créer le zip:


~~~ruby
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
~~~

Il suffit juste ensuite d'envoyer le contenu du fichier avec la méthode [`send_data`][send_data] et d'envoyer le contenu du zip. Nous utilisons la méthode [`respond_to`][respond_to] pour envoyer l'archive lorsque le format demandé est un zip.

~~~ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController

  # ...

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

end
~~~

> Vous pouvez voir le [fichier complet ici](https://github.com/madeindjs/zip_example/blob/a0fab8ec8d85bf839948c84a11badaa61b766268/app/controllers/users_controller.rb).

Les tests passent désormais

~~~
$ rake test
Run options: --seed 43367

# Running:

........

Finished in 0.220150s, 36.3389 runs/s, 49.9660 assertions/s.
8 runs, 11 assertions, 0 failures, 0 errors, 0 skips
~~~

### Factorisation

Nous allons peut-être être amené à utiliser ce code pour d'autres modèles. Afin de **factoriser** cela, Rails nous offre un excellent outil: les [`ActiveSupport::Concern`][concerns_api]!

Pour cela, il suffit créer un module dans le dossier *app/controllers/concerns* et de le faire hériter de [`ActiveSupport::Concern`][concerns_api]. Ensuite, je **déplace** toutes les méthodes que nous avons crées jusqu'ici. Et, pour utiliser notre *concern*, je crée une méthode `send_zip` (je l'utiliserai dans le *controller*).

~~~ruby
# app/controllers/concerns/generate_zip.rb

module GenerateZip
  extend ActiveSupport::Concern

  protected

  # Zip all given files into a zip and send it with `send_data`
  #
  # @param active_storages [ActiveStorage::Attached::Many] files to save
  # @param filename [ActiveStorage::Attached::Many] files to save
  def send_zip(active_storages, filename: 'my.zip')
    files = save_files_on_server active_storages
    zip_data = create_temporary_zip_file files

    send_data(zip_data, type: 'application/zip', filename: filename)
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
end
~~~

Dans le *controleur*, j'`include` simplement notre *concern* et j'utilise simplement la méthode `send_zip`

~~~ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  include GenerateZip

  # ...

  # GET /users/1
  # GET /users/1.json
  def show
    respond_to do |format|
      format.html { render }
      format.zip { send_zip @user.pictures }
    end
  end

end
~~~

Et voilà. C'est quand même plus sympa, non? Vous pouvez trouver le code [ici](https://github.com/madeindjs/zip_example/commit/67a8bcb8fd6124fdb7a2c8c3f2fd85fcbd704e5b).

## Création d'une librairie

C'est très bien mais je vous sens un peu déçu... En effet, si nous voulons utiliser ce module sur un autre projet, on serait tenté de **copier/coller** le module de projets en projets.. et **c'est mal**.

Ne faites pas ça, nous pouvons aller plus loin! Nous pouvons **déplacer** notre code dans une **librairie** qui nous permettra de **réutiliser** notre *concern* dans une infinité d'autres projets!

### Création de la gem

Pour cela rien de plus facile. Quittons deux secondes notre projet et **créons** une gem avec [bundler][bundler]:

~~~bash
$ bundle gem activestorage-zip
$ cd activestorage-zip
~~~

Nous devons spécifier les **dépendances** de notre librairie. Évidement , nous avons besoin de Rails 5.2 et de [rubyzip][rubyzip]:

~~~bash
$ bundle add rails
$ bundle add rubyzip
~~~

Et ensuite, je déplace tout le concern dans le fichier

~~~ruby
# lib/active_storage/send_zip.rb
require 'active_storage/send_zip/version'
require 'rails'
require 'zip'

module ActiveStorage
  module SendZip
    extend ActiveSupport::Concern

    protected

    # ...

  end
end
~~~

> Vous pouvez consulter le [fichier complet ici](https://github.com/madeindjs/active_storage-send_zip/blob/master/lib/active_storage/send_zip.rb)

Et voilà! C'est tout! C'était vraiment simple!

### utilisation de la gem

Maintenant on va essayer d'**utiliser** notre gem sur notre projet précédent (avant de la publier sur [Rubygem](https://guides.rubygems.org/) par exemple). J' installe donc la gem en local avec cette commande:

~~~ruby
$ rake install:local
~~~

Et maintenant revenons au projet  *example_zip*. Il suffit de d'ajouter notre gem au *Gemfile*:

~~~ruby
# Gemfile
gem 'active_storage-send_zip', '~> 0.1.0'
~~~

> n'oubliez pas le `bundle install` qui va bien

et de l'utiliser dans notre *controller*:

~~~ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  include ActiveStorage::SendZip

  # ...

  # GET /users/1
  # GET /users/1.zip
  def show
    respond_to do |format|
      format.html { render }
      format.zip { send_zip @user.pictures }
    end
  end
~~~

Et pour vérifier que tout fonctionne, on relance nos tests:

~~~
$ rake test
Run options: --seed 4817

# Running:

........

Finished in 0.250440s, 31.9437 runs/s, 43.9226 assertions/s.
8 runs, 11 assertions, 0 failures, 0 errors, 0 skips
~~~

Magnifique!

Nous pouvons maintenant [publier notre gem sur rubygems.org](https://guides.rubygems.org/publishing/)

## Conclusion

Nous avons donc vu que, passé la complexité de la création du zip, l'utilisation du *concern* deviens très simple. De plus, en créant ma propre gem (ce qui est vraiment facile), j'ai pu éviter de la **duplication** de code entre plusieurs projets. J'ai aussi contribué à la communauté Rails (à mon faible niveau :) ).

Mais j'ai effleuré le sujet. Il aurait aussi été sympa de tester unitairement notre gem afin d'avoir une meilleur couverture. Nous aurions aussi put proposer une méthodes pour créer le zip directement en mémoire vive.

Mais ne vous inquiétez pas, le code est disponible sur  Github:

- l'application Rails: <https://github.com/madeindjs/zip_example>
- la gem: <https://github.com/madeindjs/active_storage-send_zip>

N’hésitez pas à *forker* ou me donner un retours sur d'éventuelles améliorations possibles.


## Liens

- <https://www.grafikart.fr/tutoriels/active-storage-1008>
- <https://stackoverflow.com/questions/50529659/download-an-active-storage-attachment-to-disc>
- <https://thinkingeek.com/2013/11/15/create-temporary-zip-file-send-response-rails/>
- <https://www.sitepoint.com/accept-and-send-zip-archives-with-rails-and-rubyzip/>
- <https://www.synbioz.com/blog/Rails_4_utilisation_des_concerns>


[active_storage_guide]: https://edgeguides.rubyonrails.org/active_storage_overview.html
[active_storage_api]: https://edgeapi.rubyonrails.org/classes/ActiveStorage.html
[active_storage_blob_download]: https://edgeapi.rubyonrails.org/classes/ActiveStorage/Blob.html#method-i-download
[active_storage_attached_many]: https://edgeapi.rubyonrails.org/classes/ActiveStorage/Attached/Many.html
[rubyzip]: https://github.com/rubyzip/rubyzip
[tdd]: https://fr.wikipedia.org/wiki/Test_driven_development
[send_data]: https://api.rubyonrails.org/classes/ActionController/DataStreaming.html#method-i-send_data
[respond_to]: https://api.rubyonrails.org/classes/ActionController/MimeResponds.html#method-i-respond_to
[concerns_api]: https://api.rubyonrails.org/classes/ActiveSupport/Concern.html
[bundler]: https://bundler.io/
