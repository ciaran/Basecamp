# Controller for the Basecamp leaf.

class Controller < Autumn::Leaf
  def did_start_up
    BasecampAPI.establish_connection!(options[:hostname], options[:username], options[:password], true)
  end

  def todo_command(stem, sender, reply_to, msg)
    cmd, args = msg.to_s.split(' ', 2)
    return "USAGE: $todo «command» [arguments] – command is one of: add, reload" if cmd.nil? or cmd.strip.empty?

    case cmd
    when 'reload'
      @todo_lists = nil
      todo_lists
    when 'add'
      list, message = args.to_s.split(' ', 2)
      if list.nil? or list.strip.empty? or message.nil? or message.strip.empty?
        return 'USAGE: $todo add <list> <message>'
      end

      owner_id = nil
      list.gsub!(/\[(\w+)\]/) do
        return "No user info for #{$1}" unless options[:users][$1]
        owner_id = options[:users][$1]['id']
        ''
      end

      list_id = nil
      todo_lists.each_key do |title|
        if title.downcase.include?(list.downcase)
          list_id = todo_lists[title]
          break
        end
      end
      return "No list matching “#{list}” found" unless list_id

      begin
        if BasecampAPI::TodoItem.create(:todo_list_id => list_id, :content => message, :responsible_party => owner_id)
          "Todo added"
        else
          "Failed"
        end
      rescue
        "Failed to add todo: #{$!}"
      end
    else
      "Unknown command #{cmd}"
    end
  end

  def journal_command(stem, sender, reply_to, msg)
    cmd, args = msg.to_s.split(' ', 2)
    return "USAGE: $journal «command» [arguments] – command is one of: add" if cmd.nil? or cmd.strip.empty?

    case cmd
    when 'add'
      message = args.to_s
      return 'USAGE: $journal add <message>' if message.nil? or message.strip.empty?

      user = options[:backpack_users][sender[:nick]]
      return "No Backpack user information for #{irc.from.nick}" unless user

      begin
        url = URI.parse("#{options[:backpack_url]}/users/#{user['id']}/journal_entries")
        req = Net::HTTP::Post.new(url.path)
        req.add_field('Content-Type', 'application/xml')
        req.body = <<-HTML
          <request>
            <token>#{user['key']}</token>
            <journal-entry>
              <body>#{message}</body>
            </journal-entry>
          </request>
        HTML
        res = Net::HTTP.new(url.host, url.port).start {|http| http.request(req) }
        (res.is_a?(Net::HTTPSuccess) or res.is_a?(Net::HTTPRedirection)) ? "OK" : "Failed"
      rescue
        "Failed to add journal entry: #{$!}"
      end
    else
      "Unknown command #{cmd}"
    end
  end

private
  def todo_lists
    # The project ID is necessary here, else only the lists assigned to the user will be returned
    @todo_lists ||= BasecampAPI::TodoList.find(:all, :params => { :project_id => options[:project_id] }).inject({}) { |lists, list| lists[list.name] = list.id.to_i; lists }
  end
end
