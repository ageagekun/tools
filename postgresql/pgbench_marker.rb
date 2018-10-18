require 'open3'
class PgbenchMarker
  LOOP_COUNTER = 5
  attr_accessor :clients, :select_flag, :cleanup_flag, :target_host, :target_port, :target_db, :total_including_tps, :total_excluding_tps

  def self.execute!(*args)
    batch = self.new(*args)
    self::LOOP_COUNTER.times do |counter|
      batch.execute_pgbench!
    end
    batch.puts_result
  end

  def initialize(clients, options={})
    self.clients      = clients
    self.target_host  = options[:target_host] || "localhost"
    self.target_port  = options[:target_port] || "5432"
    self.target_db    = options[:target_db]   || "template1"
    self.select_flag  = options[:select_only]
    self.cleanup_flag = options[:cleanup_db]
    self.total_including_tps = 0.0
    self.total_excluding_tps = 0.0
  end

  def select_only?
    !!self.select_flag
  end

  def cleanup_db?
    !!self.cleanup_flag
  end

  def uncleanup_db?
    !self.cleanup_db?
  end

  def transaction_type
    self.select_only? ? "SELECT only" : "TPC-B (sort of)"
  end

  def transaction_size
    self.select_only? ? "10000" : "500"
  end

  def options
    {
      port:        "-p #{self.target_port}",
      host:        "-h #{self.target_host}",
      client:      "-c #{self.clients}",
      transaction: "-t #{self.transaction_size}",
      select_option:  "#{"-S" if self.select_only?}",
      cleanup_option: "#{"-n" if self.uncleanup_db?}",
    }.values.compact.join(" ")
  end

  def pgbench_command
    "pgbench #{self.options} #{self.target_db}"
  end

  def execute_pgbench!
    stdout, stderr, status = Open3.capture3 self.pgbench_command
    raise "ERROR: stdout:#{stdout}, stderr:#{stderr}" unless status.success?
    including_tps, excluding_tps = stdout.scan(/(\S+)\stps\s=\s(\S+)/).map{|info| info.last.to_f}
    self.total_including_tps += including_tps
    self.total_excluding_tps += excluding_tps
  end

  def puts_result
    puts "-------------------"
    puts "-     result!!    -"
    puts "-------------------"
    puts Time.now.strftime("%Y-%m-%d %H:%M")
    puts "transaction type: #{self.transaction_type}"
    puts "transaction size: #{self.transaction_size}"
    puts "clients: #{self.clients}"
    puts "average including_tps: #{(self.total_including_tps / self.class::LOOP_COUNTER.to_f).round}"
    puts "average excluding_tps: #{(self.total_excluding_tps / self.class::LOOP_COUNTER.to_f).round}"
    puts "-------------------"
    puts ""
  end
end

(1..100).map{|num| num*2}.each do |clients|
  PgbenchMarker.execute!(clients, {:select_only => false, :cleanup_db => false})
  PgbenchMarker.execute!(clients, {:select_only => true,  :cleanup_db => false})
end
