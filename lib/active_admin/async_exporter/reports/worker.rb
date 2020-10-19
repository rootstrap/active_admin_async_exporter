# frozen_string_literal: true

module ActiveAdmin
  module AsyncExporter
    class Worker < ApplicationJob
      def perform(options = {})
        controller = options[:controller].classify.constantize.new
        columns = options[:columns]
        file_name = filename(options[:file_name], controller)

        path = Rails.root.join('tmp', file_name)

        CSV.open(path, 'wb', headers: true) do |csv|
          build_csv(csv, columns, controller, options)
        end

        file = Services::StorageService.call(path: path, name: file_name).store
        AdminReport.find(options[:admin_report_id]).update!(
          status: :ready,
          location_url: file.url
        )
      end

      private

      def proc_from_string(code_string)
        proc_string = code_from_string(code_string)
        Proc.class_eval("proc #{proc_string}")
      end

      def code_from_string(code_string)
        code_string.scan(/(do|{)\s+(\|.*\|)(.*)(end|})/m).flatten.join('')
      end

      def collection(controller, options)
        controller.current_collection.ransack(options[:query]).result
      end

      def filename(file_name, controller)
        file_name ||= controller.current_collection.name.pluralize.downcase
        [file_name, Time.current.to_i].join('_') + '.csv'
      end

      def build_csv(csv, columns, controller, options)
        headers = columns.keys
        evaluators = columns.values

        csv << headers.map(&:to_s)

        collection(controller, options).find_in_batches do |group|
          group.each do |model|
            model = model.decorate if options[:decorate_model]

            csv << csv_field_value(model, evaluators)
          end
        end
      end

      def csv_field_value(model, evaluators)
        evaluators.collect do |ev|
          value = ev[:value]

          if ev[:block]
            code_proc = proc_from_string(value)
            code_proc.yield(model)
          else
            model.send(value)
          end
        end
      end
    end
  end
end
