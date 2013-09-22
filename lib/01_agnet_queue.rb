# 
# AgentQueue
# 
# @author yshtak
# @description 
require 'thread'
class AgentQueue
  def initialize
    @empty = ConditionVariable.new
    @mutex = Mutex.new
    @q = []
  end

  def count
    @q.size
  end

  def enq v
    @mutex.synchronize do
      @q.push v
      @empty.signal if count == 1
    end
  end

  def deq
    @mutex.synchronize do
      @empty.wait(@mutex) if count == 0
      v = @q.shift
      v
    end
  end

end
