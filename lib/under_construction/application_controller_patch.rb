module UnderConstruction
  module ApplicationControllerPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        before_filter :check_under_construction
        before_filter :check_browser_restrictions
      end
    end

    module ClassMethods
    end

    module InstanceMethods
      def check_under_construction
        #return true if User.current.admin? || params[:controller] == 'account'
        @uc_period = UcPeriod.order('begin_date desc').first
        is_under_construction = false
        if @uc_period && @uc_period.active?
          if @uc_period.controller_restrictions.any?
            is_under_construction = ControllerRestriction.joins(:action_restrictions)
                                      .where("#{ControllerRestriction.table_name}.uc_period_id = :uc_period_id AND
                                              (#{ControllerRestriction.table_name}.name = 'all' OR
                                               #{ControllerRestriction.table_name}.name = :controller_name AND
                                               #{ActionRestriction.table_name}.name IN ('all', :action_name))",
                                      {:uc_period_id => @uc_period.id, :controller_name => controller_name, :action_name => action_name})
                                      .exists?
          else
            is_under_construction = true
          end
        end
        if is_under_construction
          @users = [@uc_period.user]
          render 'uc_periods/under_construction', :layout => false
        end
      end

      def check_browser_restrictions
        user_browser = Browser.new(ua: request.env['HTTP_USER_AGENT'], accept_language: 'en-us')
        unsupported_browser = false
        if Setting.plugin_under_construction.is_a?(Hash) && Setting.plugin_under_construction['enable_restrictions']
          UcBrowserRestriction.where(name: user_browser.id.to_s).each do |r|
            case r.condition
            when ''
              unsupported_browser = true
              break
            when '='
              if user_browser.version.to_f == r.version.to_f
                unsupported_browser = true
                break
              end
            when '<'
              if user_browser.version.to_f < r.version.to_f
                unsupported_browser = true
                break
              end
            when '>'
              if user_browser.version.to_f > r.version.to_f
                unsupported_browser = true
                break
              end
            end
          end
        end

        if unsupported_browser
          Rails.logger.error "\n\n ~~~~[ BROWSER RESTRICTION OCCURS ]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"+
                             "\n Time: #{Time.now}"+
                             "\n User: #{User.current.name}  (user_id=#{User.current.id})  was try to open RM from ip=#{request.remote_ip}"+
                             "\n Browser: #{user_browser.name} v.#{user_browser.version}"+
                             "\n ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
          @users = Setting.plugin_under_construction['responsible_ids'].is_a?(Array) ? User.where(id: Setting.plugin_under_construction['responsible_ids']) : []
          render 'uc_browser_restrictions/unsupported_browser', :layout => false
        end
      end
    end

  end
end