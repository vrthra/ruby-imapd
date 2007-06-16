#!/usr/local/bin/ruby
require 'webrick'
require 'thread'
require 'netutils'
require 'imapmbox'
require 'base64'

$config ||= {}
$config['version'] = '0.01dev'
$config['port'] = 1143
$config['hostname'] = Socket.gethostname.split(/\./).shift

$verbose = ARGV.shift || true
    
TAG = /^([a-zA-Z0-9]+) +(.+)$/

class MboxDB
    def MboxDB.get(user)
        return $g_mbox[user]
    end
end

class MyBox
    include MBox
    def initialize(hash)
        @hash = hash
    end
    def [](key)
        case key
        when :exists
            return [1]
        else
            return []
        end
    end
end

$g_mbox = {}
$g_mbox['me'] = {
    'INBOX' => MyBox.new({
        :exists => 100
        }),
    'postponed' => MyBox.new({:exists => 0})
}

class IMAPClient
    include NetUtils

    attr_reader :user, :state, :tag, :continue
    attr_writer :tag

    def initialize(sock, serv)
        @serv = serv
        @socket = sock
        @state = {}
        @tag = 'empty'
        @current_mbox = 'INBOX'
        carp "initializing connection from #{@peername}"
    end

    def host
        return @peername
    end

    def closed?
        return @socket.nil? || @socket.closed?
    end

    def is_valid(user,pass)
        if user =~ /^".*"$/
            user = user[1..-2]
        end
        @mailstore = MboxDB.get(user)
        return !@mailstore.nil?
    end

    def handle_capability()
        repl_capability
    end

    def handle_authlogin(user,pass)
        handle_login(user, pass)
    end

    def handle_more()
        repl_authget
    end

    def handle_auth(method)
        state['auth'] = 'USER'
        repl_authget
    end

    def handle_login(user,pass)
        carp "user = #{user}"
        carp "pass = #{pass}"
        if is_valid(user,pass)
            repl_loginok
        else
            repl_nologin
        end
    end

    def handle_select(mbox)
        carp "mbox = #{mbox}"
        # it may be quoted.
        @current_mbox = mbox
        @db = @mailstore[mbox]
        if @db
            repl_selectok
        else
            repl_noselect
        end
    end

    #>> a2 FETCH 1:4 (UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER.FIELDS (DATE FROM SUBJECT TO CC MESSAGE-ID REFERENCES CONTENT-TYPE CONTENT-DESCRIPTION IN-REPLY-TO REPLY-TO LINES LIST-POST X-LABEL)])                                                       
    #<<  * 1 FETCH (UID 1 RFC822.SIZE 6039 FLAGS (\recent) INTERNALDATE "01-Jan-1970 00:00:00 +0000" BODY[HEADER.FIELDS (Date From Subject To Cc Message-Id References Content-Type Content-Description In-Reply-To Reply-To Lines List-Post X-Label)] {473}            
    #
    #Possibly very wrong and may not work.
    def send_fetch(i,h)
        reply :untaged, '1 FETCH (UID 130104 FLAGS (Old) INTERNALDATE "20-Feb-2007 23:58:47 +0100" RFC822.SIZE 2785 '+
            'BODY[HEADER.FIELDS ("DATE" "FROM" "SUBJECT" "TO" "CC" "MESSAGE-ID" "REFERENCES" "CONTENT-TYPE" '+
            ' "CONTENT-DESCRIPTION" "IN-REPLY-TO" "REPLY-TO" "LINES" "LIST-POST" "X-LABEL")] {380}'
        reply :raw, 'Message-Id: <54E40201497DF142B06B27255953F79705DADA36 at il0015exch007u.ih.mexico.com>'
        reply :raw, 'From: "Me" <me at mexico.com>'
        reply :raw, 'To: You <You at hive.net>'
        reply :raw, 'cc: Him <Him at disco.org>'
        reply :raw, 'Subject: Re: xx'
        reply :raw, 'Date: Tue, 17 Jun 2007 19:08:59 -0500'
        reply :raw, 'Content-Type: text/plain; charset=iso-8859-1'
        reply :raw, 'List-Post: <mailto:me at max.org>'
        reply :raw, ''
        reply :raw, ')'
    end

    def handle_uidfetch(fields)
        txt =<<EOF
Message-Id: <54E40201497DF142B06B27255953F79705DADA36 at il0015exch007u.ih.mexico.com>'
From: "Me" <me at mexico.com>
To: You <You at hive.net>
cc: Him <Him at disco.org>
Subject: Re: xx'

abcd
efgh
EOF
        reply :untaged, "1 FETCH i(UID 130104 BODY[] {#{txt.length}}"
        reply :raw,txt 
        reply :raw, ')'
        repl_uidfetchok
    end

    def handle_fetch(set, fields)
        h = {
            :flags => '\Seen'
        }
        send_fetch(1,h)
        repl_fetchok
    end
    
    def handle_close()
        repl_closeok
    end
    
    def handle_noop()
        repl_noopok
    end
    
    def handle_done()
        repl_doneok
    end

    def handle_logout()
        repl_logoutok
        handle_quit
    end
    
    def handle_list(reference, mbox)
        reply :untaged, "LIST (\\Noselect) \".\" ."
        repl_listok
    end

    def handle_status(mbox, items)
        db = @mailstore[mbox]
        str = ''
        puts ">#{mbox}___#{db}<"
        items.split(/ +/).each do |i|
            str += "#{i} #{db[i]}"
        end
        reply :untaged, "STATUS (#{str})"
        repl_statusok
    end

    def get_flags(flgs)
        return flgs.collect{|f| '\\' + f.to_s + ' '}
    end
   
    def repl_capability
        reply :untaged, "CAPABILITY IMAP4REV1 AUTH=LOGIN"
        reply :tag, "OK CAPABILITY completed"
    end

    def repl_selectok
        reply :untaged, "#{@db[:exists].length} EXISTS"
        reply :untaged, "#{@db[:recent].length} RECENT"
        reply :untaged, "OK [UNSEEN #{@db[:unseen].length}] Message 0 is first unseen"
        reply :untaged, "OK [UIDVALIDITY #{@db.uid}] UIDs valid"
        reply :untaged, "FLAGS (#{get_flags(@db.flags).to_s.strip })"
        reply :untaged, "OK [PERMANENTFLAGS (#{get_flags(@db.permflags).to_s}\\*)] Limited"
        reply :tag, "OK [READ-WRITE] SELECT completed"
    end
    
    def repl_closeok
        reply :tag, "OK CLOSE completed"
    end
    
    def repl_uidfetchok
        reply :tag, "OK UID FETCH completed"
    end
    def repl_fetchok
        reply :tag, "OK FETCH completed"
    end
    
    def repl_noopok
        reply :tag, "OK NOOP completed"
    end
    
    def repl_doneok
        reply :tag, "OK DONE completed"
    end
    
    def repl_logoutok
        reply :tag, "OK LOGOUT completed"
    end

    def repl_listok
        reply :tag, "OK LIST completed"
    end
    
    def repl_statusok
        reply :tag, "OK STATUS completed"
    end

    def repl_noselect
        reply :tag, "NO SELECT failed"
    end

    def repl_authget
        reply :continue, Base64.encode64(state['auth'])
    end
    
    def repl_noauthget
        reply :tag, "NO AUTHENTICATE failed"
    end

    def repl_authok
        reply :tag, "OK AUTHENTICATE completed"
    end

    def repl_loginok
        reply :tag, "OK LOGIN completed"
    end

    def repl_nologin
        reply :tag, "NO LOGIN failed"
    end
    
    def handle_abort()
        handle_quit
    end

    def handle_quit()
        @socket.close if !@socket.closed?
    end

    def handle_unknown(s)
        carp "unknown:>#{s}<"
        reply :raw, "BAD Unknown command"
    end

    def handle_connect
        reply :untaged, "OK ruby-imapd version #{$config['version']}"
    end
    
    def reply(method, *args)
        case method
        when :badlogin
            msg = *args
            raw "#{@tag} BAD LOGIN #{msg}"
        when :nologin
            msg = *args
            raw "#{@tag} NO LOGIN #{msg}"
        when :login
            msg = *args
            raw "#{@tag} OK LOGIN #{msg}"
        when :select
            msg = *args
            raw "#{@tag} OK SELECT #{msg}"
        when :raw
            arg = *args
            raw arg
        when :tag
            arg = *args
            raw "#{@tag} #{arg}"
        when :untaged
            arg = *args
            raw "* #{arg}"
        when :continue
            arg = *args
            raw "+ #{arg}"
        end
    end
    
    def raw(arg, abrt=false)
        begin
        carp "--> #{arg}"
        @socket.print arg.chomp + "\r\n" if !arg.nil?
        rescue Exception => e
            carp "<#{self.userprefix}>#{e.message}"
            handle_abort()
            raise e if abrt
        end
    end
end

class IMAPServer < WEBrick::GenericServer
    include NetUtils

    def run(sock)
        client = IMAPClient.new(sock, self)
        client.handle_connect
        imap_listen(sock, client)
    end

    def hostname
        begin
            sockaddr = @socket.getsockname
            begin
                return Socket.getnameinfo(sockaddr, Socket::NI_NAMEREQD).first
            rescue 
                return Socket.getnameinfo(sockaddr).first
            end
        rescue
            return @socket.peeraddr[2]
        end
    end

    def imap_listen(sock, client)
        begin
            while !sock.closed? && !sock.eof?
                buf = ''
                while true
                    buf += sock.gets
                    if buf[-1] == 10
                        break
                    end
                end
                handle_client_input(buf.chomp, client)
            end
        rescue Exception => e
            carp e
        end
        client.handle_abort()
    end

    def strip_quote(s)
        return $1 if s =~ /^"(.*)"$/
        return s
    end

    def handle_client_input(input, client)
        carp "<-- #{input}"
        s = input

        case input
        when TAG
            client.tag = $1
            s = $2
        end

        case s
        when /^[ ]*$/
            return
        when /^CAPABILITY$/i
            client.handle_capability()
        when /^AUTHENTICATE +([^ ]+) *$/i
            client.handle_auth($1.strip)
        when /^LOGIN +([^ ]+) +([^ ]+) *$/i
            client.handle_login($1.strip, $2.strip)
        when /^SELECT +([^ ]+) *$/i
            client.handle_select(strip_quote($1.strip))
        when /^FETCH +([^ ]+) (.+)$/i
            client.handle_fetch($1.strip, $2.strip)
        when /^UID FETCH (.+)$/i
            client.handle_uidfetch($1.strip)
        when /^CLOSE *$/i
            client.handle_close()
        when /^LOGOUT *$/i
            client.handle_logout()
        when /^LIST +([^ ]+) +([^ ]+) *$/i
            client.handle_list($1.strip, $2.strip)
        when /^STATUS +([^ ]+) +\(([^\)]+)\) *$/i
            client.handle_status(strip_quote($1.strip), $2.strip)
        when /^NOOP */i
            client.handle_noop()
        when /^DONE */i
            client.handle_done()
        when /^EVAL (.*)$/i
            #strictly for debug
            client.handle_eval($1)
        else
            case client.state['auth']
            when /USER/
                @user = Base64.decode64(s)
                client.state['auth'] = 'PASS'
                client.handle_more()
            when /PASS/
                @pass = Base64.decode64(s)
                client.state['auth'] = 'AUTH'
                client.handle_authlogin(@user, @pass)
            else
                client.handle_unknown(s)
            end
        end
    end
end


if __FILE__ == $0
    s = IMAPServer.new( :Port => $config['port'] )
    begin
        while arg = ARGV.shift
            case arg
            when /-v/
                $verbose = true
            end
        end
        trap("INT"){ 
            s.carp "killing #{$$}"
            system("kill -9 #{$$}")
            s.shutdown
        }
        s.start
    rescue Exception => e
        s.carp e
    end
end
