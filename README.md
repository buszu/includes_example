# What will we do?

We will build a bookshelf app to list books with (or without) authors data. There will be a single `#index` action and some seeds. This will be an example app to show how you can give a user control on included sub-resources in a REST-ish API.

# "Acceptance Criteria"

- User can list the books.
- User can pass `includes` query parameter to load associated resources (`author`).
- `includes` query parameter has a format of string: comma separated words, representing nested resources.
- We should have some constants that define which resources are includeable for which action.

# Tools
We will use `blueprinter` as a serializer, because it's format agnostic and quite flexible. This is an only gem we will add to rails' standard toolset.

# The app

Let's create an example app. We're not adding test framework as it's out of our scope.

```bash
rails new bookshelf -T
```

Now create `Author` model:

```bash
rails g model author name:string
#=>	invoke  active_record
#=>	create    db/migrate/20211224084524_create_authors.rb
#=>	create    app/models/author.rb
```

And `Book`:

```bash
rails g model book author:references title:string
# => invoke  active_record
# => create    db/migrate/20211224084614_create_books.rb
# => create    app/models/book.rb
```

We will need some seeds:

```ruby
# db/seeds.rb

dumas = Author.create(name: 'Alexandre Dumas')
lewis = Author.create(name: 'C.S. Lewis')
martin = Author.create(name: 'Robert C. Martin')

Book.create(author: dumas, title: 'The Three Musketeers')
Book.create(author: lewis, title: 'The Lion, the Witch and the Wardrobe')
Book.create(author: martin, title: 'Clean Code')
```

And now we are ready to run migrations and seed the db:

```bash
rails db:migrate && rails db:seed
```

Let's add `has_many` for books in `Author` model:

```ruby
# app/models/author.rb

class Author < ApplicationRecord
  has_many :books
end
```

It's time to write a controller that will return our data. We will use `API` namespace, so first let's add an acronym to inflections:

```ruby
# config/initializers/inflections.rb

ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym 'API'
end
```

Ok, let's add our serializer to `Gemfile`:

```ruby
# Add to Gemfile

gem 'blueprinter'
```

And of course install it:

```bash
bundle install
```

Then we can build our blueprints:

```ruby
# app/blueprints/author_blueprint.rb

class AuthorBlueprint < Blueprinter::Base
  identifier :id

  fields :name
end
```

```ruby
# app/blueprints/book_blueprint.rb

class BookBlueprint < Blueprinter::Base
  identifier :id

  fields :title

  association :author, blueprint: AuthorBlueprint
end
```

Add a base controller for `API`:

```ruby
# app/controllers/api/v1/base_controller.rb

module API
  module V1
    class BaseController < ActionController::API
    end
  end
end
```

And the draft version of our `BooksController`:

```ruby
# app/controllers/api/v1/books_controller.rb

module API
  module V1
    class BooksController < BaseController
      def index
        books = Book.all

        render json: BookBlueprint.render(books)
      end
    end
  end
end
```

We also must define routing of course:

```ruby
# config/routes.rb

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :books, only: :index
    end
  end
end
```

Let's test what we've done so far:

```bash
rails s
```

```bash
curl http://localhost:3000/api/v1/books

# => [{"id":1,"author":{"id":1,"name":"Alexandre Dumas"},"title":"The Three Musketeers"},{"id":2,"author":{"id":2,"name":"C.S. Lewis"},"title":"The Lion, the Witch and the Wardrobe"},{"id":3,"author":{"id":3,"name":"Robert C. Martin"},"title":"Clean Code"}]
```

The data seem to be fine, what about logs?

```
# request logs (n+1)

Started GET "/api/v1/books" for 127.0.0.1 at 2021-12-24 10:19:40 +0100
Processing by API::V1::BooksController#index as */*
  Book Load (0.1ms)  SELECT "books".* FROM "books"
  ↳ app/controllers/api/v1/books_controller.rb:7:in `index'
  Author Load (0.1ms)  SELECT "authors".* FROM "authors" WHERE "authors"."id" = ? LIMIT ?  [["id", 1], ["LIMIT", 1]]
  ↳ app/controllers/api/v1/books_controller.rb:7:in `index'
  Author Load (0.1ms)  SELECT "authors".* FROM "authors" WHERE "authors"."id" = ? LIMIT ?  [["id", 2], ["LIMIT", 1]]
  ↳ app/controllers/api/v1/books_controller.rb:7:in `index'
  Author Load (0.1ms)  SELECT "authors".* FROM "authors" WHERE "authors"."id" = ? LIMIT ?  [["id", 3], ["LIMIT", 1]]
  ↳ app/controllers/api/v1/books_controller.rb:7:in `index'
Completed 200 OK in 6ms (Views: 0.1ms | ActiveRecord: 0.4ms | Allocations: 3134)
```

By using association in our serializers we introduced `n+1` problem. We want to eliminate it by adding user a control on what he requests in this endpoint. So he should be able to either load only books, or pass the includes parameter and get authors as well, but preferably without the `n+1`.

Let's define a constant that will keep an information about what assocs of books user can include in `books#index` action:

```ruby
# lib/constants/books/includes.rb

module Constants
  module Books
    module Includes
      ALLOWED = {
        index: %i[
          author
        ].freeze
      }.freeze
    end
  end
end
```

Next, we define a namespace for empty object constants:

```ruby
# lib/constants/empty.rb

module Constants
  module Empty
    HASH = {}.freeze
  end
end
```

And here's our main service for permitting includes. I think the code is pretty self-explanatory, some pieces of `magic` are only allocated in `#default_resources_key` and `#default_purpose`. These methods are defined to allow us to call permit includes passing only  params in rails' controllers. The output will be the hash that stores `true` for each permitted inclusion.

```ruby
# app/services/permit_includes.rb

require 'constants/empty'
require 'constants/books/includes'

class PermitIncludes
  Empty = Constants::Empty

  COMMA = ','
  SLASH = '/'

  INCLUDES_FORMAT = /\A[a-z]+(,[a-z]+)*\z/.freeze
  ALLOWED_INCLUDES = {
    books: Constants::Books::Includes::ALLOWED
  }.freeze

  def call(params, resources: default_resources_key(params), purpose: default_purpose(params))
    return Empty::HASH unless includes_sent?(params)
    return Empty::HASH unless includes_valid?(params)

    requested_includes = parse_includes(params)
    allowed_includes = filter_includes(requested_includes, resources, purpose)

    allowed_includes.index_with(true)
  end

  private

  def default_resources_key(params)
    raise(ArgumentError, 'params :controller key must be a string') unless params[:controller].is_a?(String)

    params[:controller].split(SLASH).last&.to_sym
  end

  def default_purpose(params)
    raise(ArgumentError, 'params :action key must be a string') unless params[:action].is_a?(String)

    params[:action].to_sym
  end

  def includes_sent?(params)
    params.key?(:includes)
  end

  def includes_valid?(params)
    return false unless params[:includes].is_a?(String)

    params[:includes].match?(INCLUDES_FORMAT)
  end

  def parse_includes(params)
    params[:includes].split(COMMA).map(&:to_sym)
  end

  def filter_includes(requested_includes, resources_key, purpose)
    requested_includes & ALLOWED_INCLUDES[resources_key][purpose]
  end
end
```

Now we need to use the keys to load includes and pass the inlcudes hash itself to the serializer:

```ruby
# app/controllers/api/v1/books_controller.rb

module API
  module V1
    class BooksController < BaseController
      def index
        includes = PermitIncludes.new.call(params)
        books = Book.includes(includes.keys).all

        render json: BookBlueprint.render(books, includes: includes)
      end
    end
  end
end
```

And this is how we must tweak our serializer - we load the association only if included:

```ruby
# app/blueprints/book_blueprint.rb
class BookBlueprint < Blueprinter::Base
  identifier :id

  fields :title

  association :author, blueprint: AuthorBlueprint,
                       if: ->(_field_name, _book, options) {
                         options[:includes] && options[:includes][:author]
                       }
end

```

Let's test it again:

```bash
rails s
```

```bash
curl http://localhost:3000/api/v1/books
# => [{"id":1,"title":"The Three Musketeers"},{"id":2,"title":"The Lion, the Witch and the Wardrobe"},{"id":3,"title":"Clean Code"}]
```

```
# request logs (we only load books)
Started GET "/api/v1/books" for ::1 at 2021-12-24 10:33:41 +0100
Processing by API::V1::BooksController#index as */*
   (0.1ms)  SELECT sqlite_version(*)
  ↳ app/controllers/api/v1/books_controller.rb:8:in `index'
  Book Load (0.1ms)  SELECT "books".* FROM "books"
  ↳ app/controllers/api/v1/books_controller.rb:8:in `index'
Completed 200 OK in 9ms (Views: 0.1ms | ActiveRecord: 0.9ms | Allocations: 4548)
```

Good, we haven't passed the includes so got only books, without authors. Let's now request them:

```bash
curl 'http://localhost:3000/api/v1/books?includes=author'
# => [{"id":1,"author":{"id":1,"name":"Alexandre Dumas"},"title":"The Three Musketeers"},{"id":2,"author":{"id":2,"name":"C.S. Lewis"},"title":"The Lion, the Witch and the Wardrobe"},{"id":3,"author":{"id":3,"name":"Robert C. Martin"},"title":"Clean Code"}]% 
```

```
# request logs (eliminated n+1)

Started GET "/api/v1/books?includes=author" for ::1 at 2021-12-24 10:38:23 +0100
Processing by API::V1::BooksController#index as */*
  Parameters: {"includes"=>"author"}
  Book Load (0.1ms)  SELECT "books".* FROM "books"
  ↳ app/controllers/api/v1/books_controller.rb:8:in `index'
  Author Load (0.2ms)  SELECT "authors".* FROM "authors" WHERE "authors"."id" IN (?, ?, ?)  [["id", 1], ["id", 2], ["id", 3]]
  ↳ app/controllers/api/v1/books_controller.rb:8:in `index'
Completed 200 OK in 17ms (Views: 0.1ms | ActiveRecord: 0.7ms | Allocations: 7373)
```

Cool! We got the association loaded and eliminated `n+1` problem. The service can be used for any resource, all we want to do is to add allowed inlcudes constants in the proper format and add them to `PermitIncludes::ALLOWED_INCLUDES`.

We have to remember that this should be probably used with pagination (and caution) because including associations can "eat" a lot of memory.