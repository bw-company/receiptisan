# frozen_string_literal: true

require_relative 'parser/master_handler'
require_relative 'parser/receipt_type_builder'
require_relative 'parser/comment_content_builder'
require_relative 'parser/buffer'
require_relative 'parser/processor'

module Receiptisan
  module Model
    module ReceiptComputer
      class DigitalizedReceipt
        class Parser
          ReceiptType   = DigitalizedReceipt::Receipt::Type
          Comment       = Receipt::Tekiyou::Comment
          FILE_ENCODING = 'Shift_JIS'

          # @param handler [MasterHandler]
          def initialize(handler, logger)
            @handler                 = handler
            @logger                  = logger
            @buffer                  = Parser::Buffer.new
            @current_processor       = nil
            sy_processor             = Processor::SYProcessor.new(@handler)
            @processors              = {
              'IR' => Processor::IRProcessor.new,
              'RE' => Processor::REProcessor.new,
              'HO' => Processor::HOProcessor.new,
              'KO' => Processor::KOProcessor.new,
              'SY' => sy_processor,
              'SJ' => Processor::SJProcessor.new,
              'SI' => Processor::SIProcessor.new(@handler),
              'IY' => Processor::IYProcessor.new(@handler),
              'TO' => Processor::TOProcessor.new(@handler),
            }
            @comment_content_builder = Parser::CommentContentBuilder.new(@handler, sy_processor)
          end

          # @param path_of_uke [String]
          # @return [DigitalizedReceipt]
          def parse(path_of_uke)
            buffer.prepare(path_of_uke)

            File.open(path_of_uke, "r:#{FILE_ENCODING}:UTF-8") do | f |
              f.each_line(chomp: true).with_index { | line, index | parse_line(line2values(line), index) }
            end

            buffer.close
          end

          private

          # @param line [String]
          # @return [Array<String, nil>]
          def line2values(line)
            line.tr('"', '').split(',').map { | value | value.empty? ? nil : value }
          end

          # @param values [Array<String, nil>]
          # @return [void]
          # rubocop:disable Metrics/CyclomaticComplexity
          def parse_line(values, line_index)
            @current_processor = @processors[record_type = values.first]

            case record_type
            when 'IR' then process_ir(values)
            when 'RE'
              process_re(values)
              handler.prepare(buffer.current_shinryou_ym)
            when 'HO' then process_ho(values)
            when 'KO' then process_ko(values)
            when 'SN' then process_sn(values)
            when 'SY' then process_sy(values)
            when 'SJ' then process_sj(values)
            when 'SI' then process_si(values)
            when 'IY' then process_iy(values)
            when 'TO' then process_to(values)
            when 'CO' then process_co(values)
            when 'GO', 'JD', 'MF', nil
              ignore
            else
              record_type
            end
          rescue StandardError => e
            # ブロックをつかっていないのはスタックトレースも表示するため
            @logger.error 'Exception occurred while parsing %s:%d:%s' % [
              buffer.uke_file_path,
              line_index + 1,
              values.join(','),
            ]
            @logger.error e
          end
          # rubocop:enable Metrics/CyclomaticComplexity

          # @param values [Array<String, nil>]
          # @return [void]
          def process_ir(values)
            buffer.new_digitalized_receipt(current_processor.process(values))
          end

          # @param values [Array<String, nil>]
          # @return [void]
          def process_re(values)
            buffer.new_receipt(current_processor.process(values, buffer.current_audit_payer))
            buffer.latest_kyuufu_wariai    = current_processor.kyuufu_wariai
            buffer.latest_teishotoku_kubun = current_processor.teishotoku_kubun
          end

          # @param values [Array<String, nil>]
          # @return [void]
          def process_ho(values)
            buffer.add_iryou_hoken(
              current_processor.process(values, buffer.latest_kyuufu_wariai, buffer.latest_teishotoku_kubun)
            )
          end

          # @param values [Array<String, nil>]
          # @return [void]
          def process_ko(values)
            buffer.add_kouhi_futan_iryou(current_processor.process(buffer.nyuuin?, values))
          end

          # SN行を読込む
          #
          # 枝番を読込むだけ
          #
          # @param values [Array<String, nil>]
          # @return [void]
          def process_sn(values)
            buffer.current_iryou_hoken.update_edaban(values[Record::SN::C_枝番])
          end

          def process_sy(values)
            buffer.add_shoubyoumei(current_processor.process(values))
          end

          def process_si(values)
            wrap_as_cost(current_processor.process(values), Record::SI, values)
          end

          def process_iy(values)
            wrap_as_cost(current_processor.process(values), Record::IY, values)
          end

          def process_to(values)
            wrap_as_cost(current_processor.process(values), Record::TO, values)
          end

          def process_co(values)
            master_comment = handler.find_by_code(Master::Treatment::Comment::Code.of(values[Record::CO::C_レセ電コード]))
            comment        = Comment.new(
              master_item:         master_comment,
              appended_content:    @comment_content_builder.build(master_comment.pattern, values[Record::CO::C_文字データ]),
              shinryou_shikibetsu: Receipt::ShinryouShikibetsu.find_by_code(values[Record::CO::C_診療識別]),
              futan_kubun:         Receipt::FutanKubun.find_by_code(values[Record::CO::C_負担区分])
            )

            buffer.add_tekiyou(comment)
          end

          def process_sj(values)
            buffer.add_shoujou_shouki(current_processor.process(values))
          end

          def wrap_as_cost(resource, column_definition, values)
            cost = Receipt::Tekiyou::Cost.new(
              resource:            resource,
              shinryou_shikibetsu: Receipt::ShinryouShikibetsu.find_by_code(values[column_definition::C_診療識別]),
              futan_kubun:         Receipt::FutanKubun.find_by_code(values[column_definition::C_負担区分]),
              tensuu:              values[column_definition::C_点数]&.to_i,
              kaisuu:              values[column_definition::C_回数]&.to_i
            )

            comment_range = column_definition::C_コメント_1_コメントコード..column_definition::C_コメント_3_文字データ
            # @param code [String]
            # @param appended_value [String]
            values[comment_range].each_slice(2) do | code, appended_value |
              next if code.nil?

              master_comment = handler.find_by_code(Master::Treatment::Comment::Code.of(code))
              comment        = Comment.new(
                master_item:         master_comment,
                appended_content:    @comment_content_builder.build(master_comment.pattern, appended_value),
                shinryou_shikibetsu: cost.shinryou_shikibetsu,
                futan_kubun:         cost.futan_kubun
              )

              cost.add_comment(comment)
            end

            buffer.add_tekiyou(cost)
          end

          # @return [void]
          def ignore; end

          # @!attribute [r] buffer
          #   @return [Buffer]
          # @!attribute [r] handler
          #   @return [MasterHandler]
          attr_reader :buffer, :handler, :current_processor
        end
      end
    end
  end
end