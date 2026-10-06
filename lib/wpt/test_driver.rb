# frozen_string_literal: true

require "json"
require "dommy"

module DommyConformance
  module Wpt
    # The Ruby half of the testdriver.js stand-in: WPT's test_driver.click /
    # send_keys / Actions, performed by Dommy's Interaction layer as trusted
    # user input (EventSynthesis / KeySender) instead of by a WebDriver
    # backend. Installed on the page as `__dommyTestDriver`; the JS half
    # (Resources::TESTDRIVER_SHIM) wraps each call in a resolved promise.
    #
    # Pointer actions need a target element: an action with an element
    # origin uses it; a bare viewport coordinate cannot be hit-tested
    # without layout, so it lands on the body (which is "outside" every
    # popover and dialog — what such coordinates are mostly used for).
    class TestDriver
      include ::Dommy::Bridge::Methods
      js_methods %w[click sendKeys actions]

      # WebDriver's key codes (the Unicode private-use characters it maps
      # named keys to) as KeySender keys; the modifiers are chord heads.
      WEBDRIVER_KEYS = {
        "" => :backspace, "" => :tab, "" => :enter, "" => :enter,
        "" => :escape, "" => :space, "" => :page_up, "" => :page_down,
        "" => :end, "" => :home, "" => :arrow_left, "" => :arrow_up,
        "" => :arrow_right, "" => :arrow_down, "" => :delete,
      }.freeze
      WEBDRIVER_MODIFIERS = {
        "" => :shift, "" => :shift, "" => :control, "" => :control,
        "" => :alt, "" => :alt, "" => :meta, "" => :meta,
      }.freeze

      def initialize(document)
        @document = document
      end

      def __js_get__(_key) = ::Dommy::Bridge::ABSENT

      def __js_call__(method, args)
        case method
        when "click" then click(args[0])
        when "sendKeys" then send_keys(args[0], args[1].to_s)
        when "actions" then actions(::JSON.parse(args[0].to_s), args[1] || [])
        end
        nil
      end

      private

      def interaction = ::Dommy::Interaction

      def click(element)
        interaction::EventSynthesis.click(element) if element.is_a?(::Dommy::Element)
      end

      # WebDriver "Element Send Keys": focus the element, then type into
      # whatever has the focus.
      def send_keys(element, text)
        return unless element.is_a?(::Dommy::Element)

        interaction::EventSynthesis.focus(element)
        document = element.owner_document
        target = document.__internal_focused_element__ || element
        sender = key_sender(document)
        held = []
        text.each_char do |char|
          if (modifier = WEBDRIVER_MODIFIERS[char])
            # A modifier in send_keys stays down for the rest of the string.
            held << modifier unless held.include?(modifier)
            next
          end
          key = WEBDRIVER_KEYS[char] || char
          target = document.__internal_focused_element__ || document.body || target
          sender.dispatch(target, held.empty? ? key : [*held, key])
        end
      end

      # A serialized test_driver.Actions sequence, ticks in order.
      def actions(sources, elements)
        document = @document
        modifiers = []
        pointer_target = document.body
        pointer_down_target = nil
        ticks = sources.map { |s| s["actions"].size }.max.to_i
        ticks.times do |i|
          sources.each do |source|
            action = source["actions"][i]
            next if action.nil?

            case [source["type"], action["type"]]
            in ["key", "keyDown"]
              value = action["value"].to_s
              if (modifier = WEBDRIVER_MODIFIERS[value])
                modifiers << modifier
                key_target(document).then do |t|
                  name, code, = interaction::KeySender::MODIFIERS[modifier]
                  interaction::EventSynthesis.keydown(t, name, code, modifiers_init(modifiers))
                end
              else
                key = WEBDRIVER_KEYS[value] || value
                key_sender(document).dispatch(key_target(document), key, modifiers_init(modifiers))
              end
            in ["key", "keyUp"]
              value = action["value"].to_s
              if (modifier = WEBDRIVER_MODIFIERS[value])
                modifiers.delete(modifier)
                name, code, = interaction::KeySender::MODIFIERS[modifier]
                interaction::EventSynthesis.keyup(key_target(document), name, code, modifiers_init(modifiers))
              end
            in ["pointer", "pointerMove"]
              origin = action["origin"]
              pointer_target =
                if origin.is_a?(Integer) && elements[origin].is_a?(::Dommy::Element)
                  elements[origin]
                else
                  document.body
                end
            in ["pointer", "pointerDown"]
              target, backdrop = interaction::EventSynthesis.hit_target(pointer_target)
              next if target.nil?

              button = action["button"].to_i
              init = interaction::EventSynthesis.mouse_init.merge("button" => button)
              interaction::EventSynthesis.press(target, init, backdrop)
              if button == 2
                menu = ::Dommy::PointerEvent.new("contextmenu", interaction::EventSynthesis.pointer_init(init))
                interaction::EventSynthesis.dispatch(target, menu)
              end
              pointer_down_target = [target, backdrop]
            in ["pointer", "pointerUp"]
              target, backdrop = interaction::EventSynthesis.hit_target(pointer_target)
              next if target.nil?

              button = action["button"].to_i
              init = interaction::EventSynthesis.mouse_init.merge("button" => button)
              interaction::EventSynthesis.release(target, init, backdrop)
              if pointer_down_target&.first.equal?(target)
                type = button.zero? ? "click" : "auxclick"
                event = ::Dommy::PointerEvent.new(type, interaction::EventSynthesis.pointer_init(init.merge("detail" => 1)))
                interaction::EventSynthesis.dispatch(target, event)
              end
              pointer_down_target = nil
            else
              nil
            end
          end
        end
      end

      def key_target(document) = document.__internal_focused_element__ || document.body

      def modifiers_init(modifiers)
        modifiers.to_h { |m| [interaction::KeySender::MODIFIERS[m][2], true] }
      end

      def key_sender(document)
        finder = interaction::Locator.new(document)
        interaction::KeySender.new(interaction::FieldInteractor.new(finder, document),
          submit_button_predicate: ->(el) { el.respond_to?(:type) && %w[submit image].include?(el.type.to_s) })
      end
    end
  end
end
