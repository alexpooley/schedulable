module Schedulable

  module ActsAsSchedule
    extend ActiveSupport::Concern
   
    included do
      serialize :day
      serialize :day_of_week, Hash

      belongs_to :schedulable, polymorphic: true
      # 'has_many occurrences_association' defined in acts_as_schedulable

      after_initialize :update_schedule
      before_save :update_schedule
      after_save :build_occurrences#, if: ->(s) {s.previous_changes.any?}

      validates_presence_of :rule
      validates_presence_of :time
      validates_presence_of :date, if: Proc.new { |schedule| schedule.rule == 'singular' }
      validate :validate_day, if: Proc.new { |schedule| schedule.rule == 'weekly' }
      validate :validate_day_of_week, if: Proc.new { |schedule| schedule.rule == 'monthly' }

      def to_icecube
        return @schedule
      end

      def to_s
        message = ""
        if self.rule == 'singular'
          # Return formatted datetime for singular rules
          datetime = DateTime.new(date.year, date.month, date.day, time.hour, time.min, time.sec, time.zone)
          message = I18n.localize(datetime)
        else
          # For other rules, refer to icecube
          begin
            message = @schedule.to_s
          rescue Exception
            locale = I18n.locale
            I18n.locale = :en
            message = @schedule.to_s
            I18n.locale = locale
          end
        end
        return message
      end

 #    def method_missing(meth, *args, &block)
 #      if @schedule.present? && @schedule.respond_to?(meth)
 #        @schedule.send(meth, *args, &block)
 #      end
 #    end

      def self.param_names
        [:id, :date, :time, :rule, :until, :count, :interval, day: [], day_of_week: [monday: [], tuesday: [], wednesday: [], thursday: [], friday: [], saturday: [], sunday: []]]
      end

      def update_schedule

        self.rule||= "singular"
        self.interval||= 1
        self.count||= 0

        time = (self.date || Date.current).to_time
        self_tz = self.time.in_time_zone if self.time
        time = time.change(
          hour: self_tz ? self_tz.hour : 0,
          min: self_tz ? self_tz.min : 0
        )
        time_string = time.strftime("%d-%m-%Y %I:%M %p")
        time = Time.zone.parse(time_string)

        @schedule = IceCube::Schedule.new(time)

        if self.rule && self.rule != 'singular'

          self.interval = self.interval.present? ? self.interval.to_i : 1

          rule = IceCube::Rule.send("#{self.rule}", self.interval)

          if self.until
            rule.until(self.until)
          end

          if self.count && self.count.to_i > 0
            rule.count(self.count.to_i)
          end

          if self.day
            days = self.day.reject(&:empty?)
            if self.rule == 'weekly'
              days.each do |day|
                rule.day(day.to_sym)
              end
            elsif self.rule == 'monthly'
              days = {}
              day_of_week.each do |weekday, value|
                days[weekday.to_sym] = value.reject(&:empty?).map { |x| x.to_i }
              end
              rule.day_of_week(days)
            end
          end
          @schedule.add_recurrence_rule(rule)
        end

      end

      private

      def validate_day
        day.reject! { |c| c.empty? }
        if !day.any?
          errors.add(:day, :empty)
        end
      end

      def validate_day_of_week
        any = false
        day_of_week.each { |key, value|
          value.reject! { |c| c.empty? }
          if value.length > 0
            any = true
            break
          end
        }
        if !any
          errors.add(:day_of_week, :empty)
        end
      end


    end
   
    module ClassMethods
      
      def acts_as_schedule(name, options = {})
        has_many name, {dependent: :destroy}.merge(options) do
          def remaining
            where("date >= ?", Time.current).order('date ASC')
          end

          def previous
            where("date < ?", Time.current).order('date DESC')
          end
        end

        # build occurrences for events if we're persisting occurrences.
        define_method :build_occurrences do
          min_date = [self.date, Time.current].max
          
          occurrence_attribute = :date 
          
          terminating = self.rule != 'singular' && (self.until.present? || self.count.to_i > 1)
          
          max_period = Schedulable.config.max_build_period || 1.year
          max_date = min_date + max_period
          
          max_date = terminating ? [max_date, (@schedule.last.to_time rescue nil)].compact.min : max_date
          
          max_count = Schedulable.config.max_build_count || 100
          max_count = terminating && @schedule.remaining_occurrences.any? ? [max_count, @schedule.remaining_occurrences.count].min : max_count

          # Get schedule occurrence dates
          times = @schedule.occurrences_between(min_date.to_time, max_date.to_time)
          times = times.first(max_count) if max_count > 0

          # build occurrences
          occurrences_assoc = self.send(name)
          times.each do |time|
            params = {date: time, schedulable: self.schedulable}
            occurrences_assoc.find_by(params) || occurrences_assoc.create(params)
          end

          # Clean up unused remaining occurrences 
          self.send(name).remaining.where.not(date: times).destroy_all
        end
      end

    end

  end

end