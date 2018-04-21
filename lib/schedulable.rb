require 'schedulable/engine' if defined? ::Rails::Engine
require 'schedulable/railtie' if defined? ::Rails::Railtie
require 'schedulable/acts_as_schedulable'
require 'schedulable/acts_as_schedule'
require 'schedulable/schedule_support'
require 'schedulable/form_helper'
require 'i18n'

module Schedulable

  class Config
    attr_accessor :max_build_count, :max_build_period, :form_helper, :simple_form, :update_mode
  end

  def self.config
    @@config||= Config.new
  end

  def self.configure
    yield self.config
  end

end
