# typed: true
# rbs_inline: enabled

module Madmin
  class PreferencesController < Madmin::ResourceController
    private

    def resource_params
      params_hash = super
      record = resource.model.new(name: params_hash.fetch("name", @record&.name))
      params_hash.delete_if { |key, _value| !record.respond_to?("#{key}=") }
      params_hash
    end
  end
end
