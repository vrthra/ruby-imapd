# an mbox view of whatever.

module MBox
    def length
        return 0
    end

    def recent
        return []
    end

    def unseen
        return []
    end 

    def uid
        return '100'
    end

    def flags
        return [:Answered, :Flagged, :Deleted, :Seen, :Draft]
    end

    def permflags
        return [:Deleted, :Seen, :Any]
    end

    def [](arg)
        case arg
        when /MESSAGES/i
            return 101
        else
            return 901
        end
    end
end

class SynchronizedStore
    def initialize
        @store = {}
        @mutex = Mutex.new
    end
    
    def method_missing(name,*args)
        @mutex.synchronize { @store.__send__(name,*args) }
    end

    def each_value
        @mutex.synchronize do
            @store.each_value {|u|
                @mutex.unlock
                yield u
                @mutex.lock
            }
        end
    end

    def keys
        @mutex.synchronize{@store.keys}
    end
end


