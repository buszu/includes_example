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
