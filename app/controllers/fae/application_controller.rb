module Fae
  class ApplicationController < ActionController::Base
    include Fae::NavItems # deprecate in Fae v2.0
    include Fae::ApplicationControllerConcern

    helper Fae::ViewHelper

    before_filter :check_disabled_environment
    before_filter :first_user_redirect
    before_filter :authenticate_user!
    before_filter :build_nav
    before_filter :set_option
    before_filter :detect_cancellation
    before_filter :set_change_user

    private

    def check_disabled_environment
      disabled_envs = Fae.disabled_environments.map { |e| e.to_s }
      return unless disabled_envs.include? Rails.env.to_s
      render template: 'fae/pages/disabled_environment.html.slim', layout: 'fae/error.html.slim'
    end

    def super_admin_only
      redirect_to fae.root_path, flash: { error: t('fae.unauthorized_error') } unless current_user.super_admin?
    end

    def admin_only
      redirect_to fae.root_path, flash: { error: t('fae.unauthorized_error') } unless current_user.super_admin? || current_user.admin?
    end

    def show_404
      render template: 'fae/pages/error404.html.slim', layout: 'fae/error.html.slim', status: :not_found
    end

    def set_option
      @option = Fae::Option.instance
    end

    def detect_cancellation
      flash.now[:error] = 'Your changes were not saved.' if params[:cancelled].present? && params[:cancelled]== "true"
    end

    def build_nav
      return unless current_user

      @fae_topnav_items = []
      @fae_sidenav_items = []

      @fae_navigation = Fae::Navigation.new(request.path, current_user)
      raise_define_structure_error unless @fae_navigation.respond_to? :structure

      if Fae.has_top_nav
        @fae_topnav_items = @fae_navigation.items
        @fae_sidenav_items = @fae_navigation.side_nav
      elsif defined?(nav_items) && nav_items.present?
        # deprecate in v2.0
        # support nav_items defined from legacy Fae::NavItems concern
        @fae_sidenav_items = nav_items
      else
        # otherwise use Fae::Navigation to define the sidenav
        @fae_sidenav_items = @fae_navigation.items
      end

      # hide sidenav on form pages
      @fae_sidenav_items = [] if params[:action] == 'new' || params[:action] == 'edit'
    end

    # redirect to login after sign out
    def after_sign_out_path_for(resource_or_scope)
      fae.new_user_session_path
    end

    # redirect to requested page after sign in
    def after_sign_in_path_for(resource)
      request.env['omniauth.origin'] || stored_location_for(resource) || fae.root_path
    end

    def first_user_redirect
      redirect_to fae.first_user_path if Fae::User.live_super_admins.blank?
    end

    def set_change_user
      Fae::Change.current_user = current_user.id if current_user.present?
    end

    def raise_define_structure_error
      raise 'Fae::Navigation#structure is not defined, please define it in `app/models/concerns/fae/navigation_concern.rb`'
    end

    def all_models
      # load of all models since Rails caches activerecord queries.
      Rails.application.eager_load!
      ActiveRecord::Base.descendants.map.reject { |m| m.name['Fae::'] || !m.instance_methods.include?(:fae_display_field) || Fae.dashboard_exclusions.include?(m.name) }
    end

  end
end
