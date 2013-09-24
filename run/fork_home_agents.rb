# coding:utf-8
DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require 'celluloid/autostart'
require "thread"
require 'parallel' ## プロセス数制限付きによる非同期処理
require "#{DIRROOT}/agents/09_home_agent"
require "#{DIRROOT}/filter/06_particle_filter"
require "awesome_print"
require "#{DIRROOT}/config/simulation_data.rb"
require "#{DIRROOT}/agents/01_power_company"
#: 初期設定
include SimulationData
PID_NUMBER= ARGV[0].nil? ? 0 : ARGV[0]
AREA= ARGV[1].nil? ? "nagoya" : ARGV[1]

loop do

end

