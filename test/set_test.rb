# frozen_string_literal: true

require_relative "test_helper"

class SetTest < Minitest::Test
  def test_normalization_value_semantics_and_serialization
    set = Inet::Set.new(8..9, 1...4, 3..5, 6..7)
    assert_equal [1..9], set.ranges
    assert_equal 1, set.size
    assert_equal 9, set.cardinality
    assert_equal 1, set.min
    assert_equal 9, set.max
    assert_predicate set, :frozen?
    assert_predicate set.ranges, :frozen?
    set.to_a.clear
    assert_equal [1..9], set.to_a
    assert_equal [1..9], set.each.to_a
    assert_same(set, set.each { |range| assert_equal 1..9, range })
  end

  def test_serialization_and_invalid_ranges
    set = Inet::Set.new(1..9)
    restored = Marshal.load(Marshal.dump(set))
    assert_equal set, restored
    assert_equal set.hash, restored.hash
    assert_equal "value", { set => "value" }[restored]
    assert_predicate restored, :frozen?
    assert_predicate Inet::Set.new, :empty?
    assert_nil Inet::Set.new.min
    assert_nil Inet::Set.new.max
    [1, nil, -1..2, 3..2, 1...1, 1.0..2.0, (1..)].each do |range|
      assert_raises(ArgumentError) { Inet::Set.new(range) }
    end
  end

  def test_relations_and_operand_validation
    outer = Inet::Set.new(1..10)
    inner = Inet::Set.new(2..3, 7..8)
    assert_equal :contains, outer.relation(inner)
    assert_equal :within, inner.relation(outer)
    assert_equal :equal, inner.relation(inner)
    assert_equal :other, inner.relation(Inet::Set.new(20..30))
    assert outer.cover?(inner)
    assert inner.subset?(outer)
    assert outer.cover?(Inet::Set.new)
    assert outer.cover?(1)
    refute outer.include?(11)
    refute outer.include?(-1)
    assert outer.overlap?(inner)
    refute outer.overlap?(Inet::Set.new(11..12))
    %i[| & - cover? subset? overlap? relation include?].each do |method|
      assert_raises(ArgumentError) { outer.public_send(method, nil) }
    end
  end

  def test_empty_and_identical_operands
    empty = Inet::Set.new
    set = Inet::Set.new(1..3, 8..10)
    assert_equal set, empty | set
    assert_same set, set | empty
    assert_same set, set.public_send(:|, set)
    assert_same set, set & set
    assert_equal empty, set & empty
    assert_equal empty, empty & set
    assert_equal empty, set - set
    assert_same set, set - empty
    assert_same empty, empty - set
    refute empty.cover?(set)
    assert_equal empty, Marshal.load(Marshal.dump(empty))
  end

  def test_operations_against_enumerated_small_sets
    random = Random.new(42)
    100.times do
      left, right = Array.new(2) do
        Inet::Set.new(*Array.new(4) do
          a = random.rand(32)
          b = a + random.rand(4)
          a..b
        end)
      end
      a, b = [left, right].map { |set| set.flat_map(&:to_a) }
      assert_equal (a | b).sort, (left | right).flat_map(&:to_a)
      assert_equal a & b, (left & right).flat_map(&:to_a)
      assert_equal a - b, (left - right).flat_map(&:to_a)
      assert_equal !!a.intersect?(b), left.overlap?(right)
      assert_equal (b - a).empty?, left.cover?(right)
    end
  end
end
