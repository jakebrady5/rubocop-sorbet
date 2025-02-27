# frozen_string_literal: true

require "spec_helper"

RSpec.describe(RuboCop::Cop::Sorbet::ObsoleteStrictMemoization, :config) do
  let(:specs) do
    [
      Gem::Specification.new("foo", "0.0.1"),
      Gem::Specification.new("bar", "0.0.2"),
    ]
  end

  before(:each) do
    allow(Bundler).to(receive(:locked_gems)).and_return(
      Struct.new(:specs).new([
        *specs,
        Gem::Specification.new("sorbet-static", "0.5.10210"),
      ]),
    )

    allow(cop).to(receive(:configured_indentation_width).and_return(2))
  end

  it "the new memoization pattern doesn't register any offense" do
    expect_no_offenses(<<~RUBY)
      def foo
        @foo ||= T.let(Foo.new, T.nilable(Foo))
      end
    RUBY
  end

  describe "the obsolete memoization pattern" do
    it "registers an offence and autocorrects" do
      expect_offense(<<~RUBY)
        def foo
          @foo = T.let(@foo, T.nilable(Foo))
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
          @foo ||= Foo.new
        end
      RUBY

      expect_correction(<<~RUBY)
        def foo
          @foo ||= T.let(Foo.new, T.nilable(Foo))
        end
      RUBY
    end

    describe "with fully qualified ::T" do
      it "registers an offence and autocorrects" do
        expect_offense(<<~RUBY)
          def foo
            @foo = ::T.let(@foo, ::T.nilable(Foo))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
            @foo ||= Foo.new
          end
        RUBY

        expect_correction(<<~RUBY)
          def foo
            @foo ||= ::T.let(Foo.new, ::T.nilable(Foo))
          end
        RUBY
      end
    end

    describe "with a complex type" do
      it "registers an offence and autocorrects" do
        expect_offense(<<~RUBY)
          def client_info_hash
            @client_info_hash = T.let(@client_info_hash, T.nilable(T::Hash[Symbol, T.untyped]))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
            @client_info_hash ||= client_info.to_hash
          end
        RUBY

        expect_correction(<<~RUBY)
          def client_info_hash
            @client_info_hash ||= T.let(client_info.to_hash, T.nilable(T::Hash[Symbol, T.untyped]))
          end
        RUBY
      end
    end

    describe "with a long initialization expression" do
      let(:max_line_length) { 90 }

      let(:config) do
        RuboCop::Config.new(
          "Layout/LineLength" => { "Max" => max_line_length },
          "Sorbet/ObsoleteStrictMemoization" => cop_config,
        )
      end

      it "registers an offence and autocorrects into a multiline expression" do
        expect_offense(<<~RUBY)
          def foo
            @foo = T.let(@foo, T.nilable(SomeReallyLongTypeName______________________________________))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
            @foo ||= some_really_long_initialization_expression______________________________________
          end
        RUBY

        expect_correction(<<~RUBY)
          def foo
            @foo ||= T.let(
              some_really_long_initialization_expression______________________________________,
              T.nilable(SomeReallyLongTypeName______________________________________),
            )
          end
        RUBY

        autocorrected_source = autocorrect_source(<<~RUBY)
          def foo
            @foo = T.let(@foo, T.nilable(SomeReallyLongTypeName______________________________________))
            @foo ||= some_really_long_initialization_expression______________________________________
          end
        RUBY

        longest_line = autocorrected_source.lines.max_by(&:length)
        expect(longest_line.length).to(be <= max_line_length)
      end
    end

    describe "with multiline initialization expression" do
      it "registers an offence and autocorrects into a multiline expression" do
        # There's special auto-correct logic to handle a multiline initialization expression, so that it
        # *doesn't* end up like this:
        #
        #   def foo
        #     @foo = T.let(multiline_method_call(
        #       foo,
        #       bar,
        #       baz,
        #     ), T.nilable(Foo))
        #   end

        expect_offense(<<~RUBY)
          def foo
            @foo = T.let(@foo, T.nilable(Foo))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
            @foo ||= multiline_method_call(
              foo,
              bar,
              baz,
            )
          end
        RUBY

        expect_correction(<<~RUBY)
          def foo
            @foo ||= T.let(
              multiline_method_call(
                foo,
                bar,
                baz,
              ),
              T.nilable(Foo),
            )
          end
        RUBY
      end

      describe "with a gap between the two lines" do
        it "registers an offence and autocorrects into a multiline expression" do
          expect_offense(<<~RUBY)
            def foo
              @foo = T.let(@foo, T.nilable(Foo))
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.

              @foo ||= multiline_method_call(
                foo,
                bar,
                baz,
              )
            end
          RUBY

          expect_correction(<<~RUBY)
            def foo
              @foo ||= T.let(
                multiline_method_call(
                  foo,
                  bar,
                  baz,
                ),
                T.nilable(Foo),
              )
            end
          RUBY
        end
      end
    end

    context "when its not the first line in a method" do
      it "registers an offence and autocorrects" do
        expect_offense(<<~RUBY)
          def foo
            some
            other
            code
            @foo = T.let(@foo, T.nilable(Foo))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
            @foo ||= Foo.new
          end
        RUBY

        expect_correction(<<~RUBY)
          def foo
            some
            other
            code
            @foo ||= T.let(Foo.new, T.nilable(Foo))
          end
        RUBY
      end
    end

    context "using an old version of Sorbet" do
      # For old versions, the obsolete memoization pattern isn't actually obsolete.

      describe "the obsolete memoization pattern" do
        it "does not register an offence" do
          allow(Bundler).to(receive(:locked_gems)).and_return(
            Struct.new(:specs).new([
              *specs,
              Gem::Specification.new("sorbet-static", "0.5.10209"),
            ]),
          )

          expect_no_offenses(<<~RUBY)
            sig { returns(Foo) }
            def foo
              @foo = T.let(@foo, T.nilable(Foo))
              @foo ||= Foo.new
            end
          RUBY
        end
      end
    end

    context "not using Sorbet" do
      # If the project is not using Sorbet, the obsolete memoization pattern might be intentional.

      describe "the obsolete memoization pattern" do
        it "does not register an offence" do
          allow(Bundler).to(receive(:locked_gems)).and_return(
            Struct.new(:specs).new([
              *specs,
            ]),
          )

          expect_no_offenses(<<~RUBY)
            sig { returns(Foo) }
            def foo
              @foo = T.let(@foo, T.nilable(Foo))
              @foo ||= Foo.new
            end
          RUBY
        end
      end
    end
  end

  describe "a mistaken variant of the obsolete memoization pattern" do
    it "registers an offence and autocorrects" do
      # This variant would have been a mistake, which would have caused the memoized value to be discarded
      # and recomputed on every call. We can fix it up into the working version.

      expect_offense(<<~RUBY)
        def foo
          @foo = T.let(nil, T.nilable(Foo))
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This two-stage workaround for memoization in `#typed: strict` files is no longer necessary. See https://sorbet.org/docs/type-assertions#put-type-assertions-behind-memoization.
          @foo ||= Foo.new
        end
      RUBY

      expect_correction(<<~RUBY)
        def foo
          @foo ||= T.let(Foo.new, T.nilable(Foo))
        end
      RUBY
    end
  end
end
