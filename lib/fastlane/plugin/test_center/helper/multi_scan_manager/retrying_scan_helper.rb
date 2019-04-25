module TestCenter
  module Helper
    module MultiScanManager
      require_relative 'device_manager'

      class RetryingScanHelper

        def initialize(options)
          @options = options
          @testrun_count = 0
        end
        
        def before_testrun
          remove_preexisting_test_result_bundles if @options[:result_bundle]
        end

        def remove_preexisting_test_result_bundles
          absolute_output_directory = File.absolute_path(@options[:output_directory])
          glob_pattern = "#{absolute_output_directory}/*.test_result"
          preexisting_test_result_bundles = Dir.glob(glob_pattern)
          FileUtils.rm_rf(preexisting_test_result_bundles)
        end

        def after_testrun(exception = nil)
          @testrun_count = @testrun_count + 1
          if exception.kind_of?(FastlaneCore::Interface::FastlaneTestFailure)
            if @options[:reset_simulators]
              @options[:simulators].each do |simulator|
                simulator.reset
              end
            end
          elsif exception.kind_of?(FastlaneCore::Interface::FastlaneBuildFailure)
            derived_data_path = File.expand_path(@options[:derived_data_path])
            test_session_logs = Dir.glob("#{derived_data_path}/Logs/Test/*.xcresult/*_Test/Diagnostics/**/Session-*.log")
            test_session_logs.sort! { |logfile1, logfile2| File.mtime(logfile1) <=> File.mtime(logfile2) }
            test_session = File.open(test_session_logs.last)
            backwards_seek_offset = -1 * [1000, test_session.stat.size].min
            test_session.seek(backwards_seek_offset, IO::SEEK_END)
            case test_session.read
            when /Test operation failure: Test runner exited before starting test execution/
              FastlaneCore::UI.message("Test runner for simulator <udid> failed to start")
            when /Test operation failure: Lost connection to testmanagerd/
              FastlaneCore::UI.error("Test Manager Daemon unexpectedly disconnected from test runner")
              FastlaneCore::UI.important("com.apple.CoreSimulator.CoreSimulatorService may have become corrupt, consider quitting it")
              if @options[:quit_core_simulator_service]
                Fastlane::Actions::RestartCoreSimulatorServiceAction.run
              else
              end
            else
              raise exception
            end
            if @options[:reset_simulators]
              @options[:simulators].each do |simulator|
                simulator.reset
              end
            end
          else
            move_test_result_bundle_for_next_run
          end
        end

        def move_test_result_bundle_for_next_run
          absolute_output_directory = File.absolute_path(@options[:output_directory])
          glob_pattern = "#{absolute_output_directory}/*.test_result"
          preexisting_test_result_bundles = Dir.glob(glob_pattern)
          unnumbered_test_result_bundles = preexisting_test_result_bundles.reject do |test_result|
            test_result =~ /.*-\d+\.test_result/
          end
          src_test_bundle = unnumbered_test_result_bundles.first
          dst_test_bundle_parent_dir = File.dirname(src_test_bundle)
          dst_test_bundle_basename = File.basename(src_test_bundle, '.test_result')
          dst_test_bundle = "#{dst_test_bundle_parent_dir}/#{dst_test_bundle_basename}-#{@testrun_count}.test_result"
          FileUtils.mkdir_p(dst_test_bundle)
          FileUtils.mv(src_test_bundle, dst_test_bundle)
        end
      end
    end
  end
end
