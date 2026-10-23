# frozen_string_literal: true

module Inet
  # 不变量是区间有序、互不相交且已合并；遍历区间而不是逐个枚举主机。
  class Set
    include Enumerable

    attr_reader :ranges, :hash

    # 校验、排序并合并区间，然后冻结集合以保证值语义。
    def initialize(*ranges)
      ordered = ranges.map { |range| interval_endpoints(range) }.sort_by(&:first)
      merged = []
      ordered.each do |first, last|
        if !merged.empty? && first <= merged.last[1] + 1
          merged.last[1] = [merged.last[1], last].max
        else
          merged << [first, last]
        end
      end
      @ranges = merged.map { |first, last| first..last }.freeze
      @hash = @ranges.hash
      freeze
    end

    # 遍历规范化后的区间；没有代码块时返回枚举器。
    def each(&block)
      return enum_for(__method__) unless block

      ranges.each(&block)
      self
    end

    # 判断集合是否没有区间。
    def empty? = ranges.empty?

    # 返回区间段数量，而不是地址或端口总数。
    def size = ranges.size

    # 返回最小端点；空集合返回 nil。
    def min = ranges.first&.begin

    # 返回最大端点；空集合返回 nil。
    def max = ranges.last&.end

    # 计算所有闭区间包含的元素总数。
    def cardinality = sum { |range| range.end - range.begin + 1 }

    # 仅按规范化后的区间比较集合内容。
    def ==(other) = other.is_a?(Set) && ranges == other.ranges

    alias eql? ==

    # 计算并集；两个集合为空或相同对象时直接复用已有值。
    def |(other)
      validate_operand!(other)
      return self if other.empty? || equal?(other)
      return other if empty?

      self.class.new(*ranges, *other.ranges)
    end

    # 用双指针扫描两个有序集合，计算交集。
    def &(other)
      validate_operand!(other)
      return self if equal?(other) || empty?
      return other if other.empty?

      result = []
      left = right = 0
      while left < size && right < other.size
        a = ranges[left]
        b = other.ranges[right]
        first = [a.begin, b.begin].max
        last = [a.end, b.end].min
        result << (first..last) if first <= last
        left += 1 if a.end <= b.end
        right += 1 if b.end <= a.end
      end
      self.class.new(*result)
    end

    # 从当前集合中减去另一个集合，逐段截去重叠部分。
    def -(other)
      validate_operand!(other)
      return self if empty? || other.empty?
      return self.class.new if equal?(other)

      result = []
      right = 0
      each do |range|
        cursor = range.begin
        right += 1 while right < other.size && other.ranges[right].end < cursor
        result.concat(subtract_interval(range, other.ranges, right))
      end
      self.class.new(*result)
    end

    # 判断整数是否落在任一规范化区间内。
    def include?(number)
      raise ArgumentError, "Membership requires an integer" unless number.is_a?(Integer)

      candidate = ranges.bsearch { |range| range.end >= number }
      candidate ? candidate.begin <= number : false
    end

    # 判断集合是否被当前集合覆盖；空集合始终被覆盖。
    def cover?(other)
      return include?(other) if other.is_a?(Integer)

      validate_operand!(other)
      return covers_interval?(other.ranges.first) if other.size == 1

      index = 0
      other.each do |range|
        index += 1 while index < size && ranges[index].end < range.begin
        return false if index == size || ranges[index].begin > range.begin || ranges[index].end < range.end
      end
      true
    end

    # 判断当前集合是否是另一个集合的子集。
    def subset?(other)
      validate_operand!(other)
      other.cover?(self)
    end

    # 判断两个有序集合是否存在重叠区间。
    def overlap?(other)
      validate_operand!(other)
      left = right = 0
      while left < size && right < other.size
        a = ranges[left]
        b = other.ranges[right]
        return true if a.overlap?(b)

        a.end < b.end ? left += 1 : right += 1
      end
      false
    end

    # 返回相等、包含、被包含或互不相同四种关系之一。
    def relation(other)
      validate_operand!(other)
      return :equal if self == other
      return :contains if cover?(other)
      return :within if subset?(other)

      :other
    end

    # 返回区间数组的浅副本，避免调用方修改内部数组。
    def to_a = ranges.dup

    # 哈希值只在当前进程有效；持久化区间，并在读取进程中重新建立冻结集合。
    def marshal_dump = ranges

    # 从持久化区间恢复集合的不变量和冻结状态。
    def marshal_load(ranges)
      initialize(*ranges)
    end

    private

    # 把合法区间统一为闭区间端点。
    def interval_endpoints(range)
      unless range.is_a?(Range) && range.begin.is_a?(Integer) && range.end.is_a?(Integer)
        raise ArgumentError, "Intervals must have integer endpoints"
      end

      first = range.begin
      last = range.end - (range.exclude_end? ? 1 : 0)
      raise ArgumentError, "Intervals must be nonnegative and ordered" if first.negative? || first > last

      [first, last]
    end

    # 对单个区间做差，调用方复用已找到的右侧起点。
    def subtract_interval(range, removed_ranges, scan)
      result = []
      cursor = range.begin
      while scan < removed_ranges.size && removed_ranges[scan].begin <= range.end
        removed = removed_ranges[scan]
        result << (cursor..(removed.begin - 1)) if removed.begin > cursor
        cursor = [cursor, removed.end + 1].max
        break if cursor > range.end

        scan += 1
      end
      result << (cursor..range.end) if cursor <= range.end
      result
    end

    # 单区间包含检查使用二分查找。
    def covers_interval?(target)
      candidate = ranges.bsearch { |range| range.end >= target.end }
      candidate ? candidate.begin <= target.begin : false
    end

    # 统一校验集合运算的右值类型。
    def validate_operand!(other)
      raise ArgumentError, "Expected a Set" unless other.is_a?(Set)
    end
  end
end
