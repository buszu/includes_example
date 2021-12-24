class BookBlueprint < Blueprinter::Base
  identifier :id

  fields :title

  association :author, blueprint: AuthorBlueprint,
                       if: ->(_field_name, _book, options) {
                         options[:includes] && options[:includes][:author]
                       }
end
