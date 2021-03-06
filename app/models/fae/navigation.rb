module Fae
  class Navigation
    include Rails.application.routes.url_helpers
    include Fae::NavigationConcern

    attr_accessor :current_path, :coordinates, :current_user, :items

    def initialize(current_path, current_user)
      @current_path = current_path
      @current_user = current_user
      @coordinates = []
      @items = recursive_authorization(structure)

      # set the coors based on current path
      find_current_hash(@items)
    end

    def side_nav
      @items[@coordinates.first][:subitems][@coordinates.second][:subitems] if @coordinates.length > 2
    end

    def search(query)
      find_items_by_text(@items, query, [])
    end

    def current_section
      @current_path.gsub(/\/new$|\/\d+\/edit/, '')
    end

    private

    def find_current_hash(array_of_items)
      @coordinates.push(0)

      array_of_items.each do |item|
        return item if item[:path] == current_section

        if item[:subitems].present?
          current_sidenav = find_current_hash(item[:subitems])
          return current_sidenav if current_sidenav.present?
        end

        increment_coordinates
      end
      # if nothing is returned, remove last coor and return nil
      @coordinates.pop
      nil
    end

    def increment_coordinates
      last_item = @coordinates.pop
      @coordinates.push(last_item + 1)
    end

    def find_items_by_text(items, query, results)
      items.each do |item|
        if item[:text].present? && item[:text].downcase.include?(query.downcase)
          results << { text: item[:text], nested_path: item[:nested_path] }
        end
        if item[:subitems].present?
          results = find_items_by_text(item[:subitems], query, results)
        end
      end
      results
    end

    def item(text, options={})
      hash = { text: text }
      hash.merge! options
      hash[:nested_path] = nested_path(hash)
      hash[:path] ||= '#'
      # prefer `subitems` over `sublinks` for new DSL but still need to support old structure in v1
      hash[:sublinks] = hash[:subitems] if hash[:subitems].present?

      # authorize link with current user
      unless can_view_path(hash[:nested_path])
        hash[:path] = '#'
        hash[:nested_path] = '#'
      end

      hash
    end

    def can_view_path(path)
      return true if path.blank?

      can_view = true
      item_controllers = path.split(/\/\d+\//)
      item_controllers.each do |item_controller|
        item_controller = item_controller.gsub(/#{fae.root_path}|\/new$|edit$/, '')
        can_view = !Fae::Authorization.access_map[item_controller] || Fae::Authorization.access_map[item_controller].include?(@current_user.role.name)
      end

      can_view
    end

    def fae
      Fae::Engine.routes.url_helpers
    end

    def nested_path(hash)
      return hash[:path] if hash[:path]

      path_from_subitems hash
    end

    def path_from_subitems(hash)
      return '#' unless hash[:subitems] && hash[:subitems].is_a?(Array)

      first_subitem = hash[:subitems].first

      if first_subitem.present?
        return first_subitem[:path] if first_subitem.present? && first_subitem[:path] != '#'

        path_from_subitems hash[:subitems].first
      end
    end

    def recursive_authorization(items)
      rejected_indexes = []
      items.each_with_index do |item, i|
        recursive_authorization(item[:subitems]) if item[:subitems].present?
        # flag for removal if there isn't active links in the item or subitems
        rejected_indexes << i if item[:nested_path] == '#' && item[:subitems].blank?
      end
      # remove flagged items in separate loop
      # removing them inline will skip the next item in the loop
      items.delete_if.with_index { |_, index| rejected_indexes.include? index }
    end

  end
end
