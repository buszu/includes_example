# frozen_string_literal: true

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
