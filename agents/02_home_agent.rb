require 'awesome_print'
require "#{File.expand_path File.dirname __FILE__}/../filter/02_particle_filter"

class HomeAgent
 attr_accessor :strage, :target
 SIM_INTERVAL = 24 * 4 # 15分刻み

 def initialize cfg={}
  config = {
   filter: 'none', # 未来予測のためのフィルターのタイプ
   max_strage: 4000.0, # 蓄電容量(Wh)
   target: 2000.0, # 目標蓄電量(Wh)
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown"
  }.merge(cfg)
  # データの初期化
  @max_strage = config[:max_strage]
  @battery = 2000.0
  @filter = filter_init config[:filter]
  @target = config[:target]
  @solars = config[:solars]
  @demands = config[:demands]
  @clock = 0
  @address = config[:address]
 end

 # 需要量のセット
 def set_demands datas
  @demands.clear
  @demands = datas
 end

 # 太陽光発電量をセット
 def set_solars datas
  @solars.clear
  @solars = datas
 end

 def select_weather type
  root = File.expand_path File.dirname __FILE__
  case type
  when "sunny"
   model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   @filter.set_model_data model
  when "rainny"
   model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   @filter.set_model_data model
  when "cloudy"
   model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   @filter.set_model_data model
  end
 end

 # 一日の行動をする
 def date_action
  results = []
  bs = []
  for cnt in 0..SIM_INTERVAL-1 do
   bs << @battery
   if cnt > (4 * 1) && cnt < (23 * 4)
    crnt_solar = @solars[cnt] # 現在時刻の発電量
    next_solar = @filter.next_value_predict crnt_solar, cnt # 次のタイムステップの発電量予測
    crnt_demand = @demands[cnt] # 現在の需要
    next_demand = @demands[cnt+1] # 次の需要

    #power_value = buy_power_2(crnt_demand,crnt_solar) # 予測考慮なし
    power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
    results << power_value
   else
    next_solar = @filter.next_value_predict @solars[cnt], cnt

    if @battery < @target
     results << @target - @battery
     @battery = @target
    else
     results << 0.0
    end

   end
  end
  return [results, bs]
 end

 # 買う量を決定（価格と量を返り値とする）
 # 引数
 #  d0: 現在の需要量
 #  d1: 次のの需要量 
 #  s0: 現在の太陽光発電量
 #  s1: 予測の太陽光発電量
 # 戦略は需要量から発電量を引いた値の正負で変わることに注意
 # 内部プログラムのt0,t1は絶対値であり，各ケース内の場合分け
 # で用いられる.
 def buy_power d0, d1, s0, s1
  t0 = (d0 - s0).abs
  t1 = (d1 - s1).abs
  value = 0.0 # 買電量の初期化
  #print "solar:#{s0}, demand:#{d0}\n"
  if (d0 - s0) > 0 && (d1 - s1) > 0 # Case 1 ------------------
   if @battery - (t0  + t1) < 0 # 予測と現在の需要和が現時点の蓄電量を超えるとき（空になる）
    value = @battery + t1 > @max_strage ? @max_strage - @battery : t0 + t1
   elsif @battery - (t0 + t1) > 0 && @battery - (t0 + t1) < @target # 未来予測後も目標値以下のとき
    value = @battery + t1 <= @max_strage ? t0 + t1 : @max_strage - @battery
    #p t1
    #p value
   elsif @battery - (t1 + t0) <= @max_strage # それ以外は買わない
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
   end
  elsif d0 - s0 > 0 && d1 - s1 <= 0 # Case 2 -------------------
   if @battery - (t0 - t1) > 0 && @battery - (t0 - t1) <= @target
    value = t0 - t1
    #p value
   elsif @battery - (t0 - t1) > @target
    if @battery - t0 < 0
     value =  t0 + @target - @battery
     #p value
    elsif @battery - t0 > 0
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    end
   end
   # Exception
   return 0.0
  elsif d0 - s0 <= 0 && d1 - s1 > 0 # Case 3 -------------------
   if @battery + t0 - t1 >= @target
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
   elsif @battery + t0 - t1 < @target
    if @battery + t0 > @max_strage
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    elsif @battery + t0 <= @max_strage
     #value = @max_strage - (@battery + t1)
     value = t1 - t0
     #p value
    end
   end
  elsif d0 - s0 <= 0 && d1 - s1 <= 0 # Case 4 -------------------
   if @battery + t0 + t1 < @target
    value = @target - (@battery + (t0 + t1))
   else
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
   end
  end
  @battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
  @battery = @battery - d0 + value
  return value 
 end

 # 現在時刻のみ見る場合の戦略
 def buy_power_2 d0, s0
  if d0 > s0
   if @battery - (d0 - s0) > @target
    @battery = @battery - (d0 - s0)
    return 0.0
   else
    value =  @target - (@battery - (d0 - s0))
    @battery = @battery - d0 + value
    return value
   end
  else
   @battery =  @battery + (s0 - d0) < @max_strage ? @battery + (s0 - d0) : @max_strage
   return 0.0
  end
 end

 # 買う相手先の選択
 def select_target id
  
 end

 # 電力を売る
 def sell_power
  
 end

 # 時間をすすめる
 def next_time time
  @clock += 1
 end

 # 1日の初期化
 def init_date
  @clock = 0
  @filter.init_data
 end

 private
 # フィルターの初期化
 def filter_init type
  case type
  when 'pf'
   return @filter = ParticleFilter.new 
  when 'none'
   return nil
  end
  return nil
 end

end
