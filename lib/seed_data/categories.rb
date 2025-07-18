# frozen_string_literal: true

module SeedData
  class Categories
    def self.with_default_locale
      SeedData::Categories.new(SiteSetting.default_locale)
    end

    def initialize(locale)
      @locale = locale
    end

    def create(site_setting_names: nil)
      I18n.with_locale(@locale) do
        categories(site_setting_names).each { |params| create_category(**params) }
      end
    end

    def update(site_setting_names: nil, skip_changed: false)
      I18n.with_locale(@locale) do
        categories(site_setting_names).each do |params|
          params.slice!(:site_setting_name, :name, :description)
          params[:skip_changed] = skip_changed
          update_category(**params)
        end
      end
    end

    def reseed_options
      I18n.with_locale(@locale) do
        categories
          .map do |params|
            category = find_category(params[:site_setting_name])
            next unless category

            { id: params[:site_setting_name], name: category.name, selected: unchanged?(category) }
          end
          .compact
      end
    end

    private

    def categories(site_setting_names = nil)
      categories = [
        {
          site_setting_name: "uncategorized_category_id",
          name: I18n.t("uncategorized_category_name"),
          description: nil,
          position: 0,
          color: "0088CC",
          text_color: "FFFFFF",
          style_type: "emoji",
          emoji: "card_file_box",
          permissions: {
            everyone: :full,
          },
          force_permissions: true,
          force_existence: true,
        },
        {
          site_setting_name: "meta_category_id",
          name: I18n.t("meta_category_name"),
          description: I18n.t("meta_category_description"),
          position: 1,
          color: "808281",
          text_color: "FFFFFF",
          style_type: "emoji",
          emoji: "thought_balloon",
          permissions: {
            everyone: :full,
          },
          force_permissions: true,
          sidebar: true,
        },
        {
          site_setting_name: "staff_category_id",
          name: I18n.t("staff_category_name"),
          description: I18n.t("staff_category_description"),
          position: 2,
          color: "E45735",
          text_color: "FFFFFF",
          style_type: "emoji",
          emoji: "shield",
          permissions: {
            staff: :full,
          },
          force_permissions: true,
          sidebar: true,
        },
        {
          site_setting_name: "general_category_id",
          name: I18n.t("general_category_name"),
          description: I18n.t("general_category_description"),
          position: 3,
          color: "25AAE2",
          text_color: "FFFFFF",
          style_type: "emoji",
          emoji: "blue_book",
          permissions: {
            everyone: :full,
          },
          force_permissions: false,
          sidebar: true,
          default_composer_category: true,
        },
      ]

      if site_setting_names
        categories.select! { |c| site_setting_names.include?(c[:site_setting_name]) }
      end

      categories
    end

    def create_category(
      site_setting_name:,
      name:,
      description:,
      position:,
      color:,
      text_color:,
      style_type:,
      emoji:,
      permissions:,
      force_permissions:,
      force_existence: false,
      sidebar: false,
      default_composer_category: false
    )
      category_id = SiteSetting.get(site_setting_name)

      if should_create_category?(category_id, force_existence)
        category =
          Category.new(
            name: unused_category_name(category_id, name),
            description: description,
            user_id: Discourse::SYSTEM_USER_ID,
            position: position,
            color: color,
            text_color: text_color,
            style_type: style_type,
            emoji: emoji,
          )

        category.skip_category_definition = true if description.blank?
        category.set_permissions(permissions)
        category.save!

        SiteSetting.set(site_setting_name, category.id)

        if sidebar
          sidebar_categories = SiteSetting.default_navigation_menu_categories.split("|")
          sidebar_categories << category.id
          SiteSetting.set("default_navigation_menu_categories", sidebar_categories.join("|"))
        end

        SiteSetting.set("default_composer_category", category.id) if default_composer_category
      elsif category = Category.find_by(id: category_id)
        if description.present? && (category.topic_id.blank? || !Topic.exists?(category.topic_id))
          category.description = description
          category.create_category_definition
        end

        if force_permissions
          category.set_permissions(permissions)
          category.save!(validate: false) if category.changed?
        end
      end
    end

    def should_create_category?(category_id, force_existence)
      return false if User.human_users.any?

      if category_id > 0
        force_existence ? !Category.exists?(category_id) : false
      else
        true
      end
    end

    def unused_category_name(category_id, name)
      category_exists =
        Category.where(
          "id <> :id AND LOWER(name) = :name",
          id: category_id,
          name: name.downcase,
        ).exists?

      category_exists ? "#{name}#{SecureRandom.hex}" : name
    end

    def update_category(site_setting_name:, name:, description:, skip_changed:)
      category = find_category(site_setting_name)
      return if !category || (skip_changed && !unchanged?(category))

      name = unused_category_name(category.id, name)
      category.name = name
      category.slug = Slug.for(name, "")
      category.save!

      if description.present? && description_post = category&.topic&.first_post
        changes = { title: I18n.t("category.topic_prefix", category: name), raw: description }
        description_post.revise(Discourse.system_user, changes, skip_validations: true)
      end
    end

    def find_category(site_setting_name)
      category_id = SiteSetting.get(site_setting_name)
      Category.find_by(id: category_id) if category_id > 0
    end

    def unchanged?(category)
      if description_post = category&.topic&.first_post
        return description_post.last_editor_id == Discourse::SYSTEM_USER_ID
      end

      true
    end
  end
end
