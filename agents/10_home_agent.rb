# coding: utf-8 
require 'bunny'
require 'celluloid/autostart'
require "#{File.expand_path File.dirname __FILE__}/../filter/06_particle_filter"
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
require "#{File.expand_path File.dirname __FILE__}/../lib/03_differential_evolutions"
#========================================================
#
# Home Agent v8.0
# 2013-07-27
#  - 新しいParticle Filterを導入
# 2013-07-30
#  - 夜間に電力をまとめて買う戦略の導入
# 2013-08-18
#  - ActorModelの導入 mailboxでメッセージを受け取るよう
#  に設定
# 2013-08-30
#  - 最適化問題の追加
#
#========================================================
class HomeAgent
 attr_accessor :strage, :target, :filter, :id
 SIM_INTERVAL = 24 * 4 # 15分刻み
 include SimulationData
 include Celluloid

 def initialize cfg={}
  config = {
   id: "nagoya01",
   filter: 'none', # 未来予測のためのフィルターのタイプ
   max_strage: 10000.0, # 蓄電容量(Wh)
   target: 500.0, # 目標蓄電量(Wh)
   buy_target_ratio: 0.35, # 30%
   sell_target_ratio: 0.75, # 40%
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown",
   strategy: NORMAL_STRATEGY,
   limit_power: 2000.0,
   partner: "pc_1",
   chunk_size: 5,
   midnight_ratio: 0.8, # 夜間に購入する目標充電率
   midnight_strategy: true, # 夜間戦略ありなし
   midnight_interval: 4,
   contractor: nil # 電力事業所エージェントのポインター
  }.merge(cfg)
  ## debug
  #ap config
  # データの初期化
  @id = config[:id]
  @partner = config[:partner]
  @simdatas = []
  @strategy = config[:strategy]
  @my_contractor = config[:contractor] # ポインター受け渡し
  @chunk_size = config[:chunk_size] # 学習データサイズ
  @midnight_ratio = config[:midnight_ratio] #
  @midnight_interval = config[:midnight_interval] #
  @midnight_strategy = config[:midnight_strategy] #
  @max_strage = config[:max_strage] # 最大容量
  @battery = 2000.0 # 蓄電量の初期値
  @pre_battery = 2000.0 # 初期値
  @address = config[:address] # 地域や住所（ex, nagoya, okazaki）
  @weather = -1 # none 
  @oneday_buys = Array.new((1440/TIMESTEP), 0.0) # 一日の買った電力をタイプステップごとで記録し学習
  @oneday_sells = Array.new((1440/TIMESTEP), 0.0) # 一日の売った電力をタイムステップごとで記録し学習
  @oneday_battery = Array.new((1440/TIMESTEP), 0.0) 
  @filter = filter_init config[:filter]
  @target = config[:target] # 目標充電量
  @buy_target = @max_strage * config[:buy_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @sell_target = @max_strage * config[:sell_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @solars = config[:solars] # 太陽光発電量のデータ（シミュレーション用）
  @demands = config[:demands] # 需要（電力消費）データ（シミュレーション用）
  @clock = {:step => 0, :day => 0} # エージェント内時計
  ###################################
  @bunny = Bunny.new
  @bunny.start
  @ch = @bunny.create_channel
  @my_q = @ch.queue("#{@id}",:auto_delete => true)
  @reply_q = @ch.queue("#{@partner}", :auto_delete => true)
  ready_box # Queueを受付可能状態にする
  ###################################
  # 学習データ
  @trains={
   demands:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   solars:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   buys:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   sells:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   p_sell_price:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   p_purchase_price:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   battery:{
     SUNNY => [], RAINY => [], CLOUDY => []
   },
  }
  #@buy_times = (0...(1440/TIMESTEP)).map{|i| (25.0*Random.rand(10.0)+10) + Random.rand(100.0)} # 一日の間に時間別で購入する量の配列
  #@sell_times = (0...(1440/TIMESTEP)).map{|i| (25.0*Random.rand(10.0)+10) + Random.rand(85.0)} # 一日の間に時間別に販売する量の配列
  @buy_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別で購入する量の配列
  @day_batteries = Array.new((1440/TIMESTEP),0.0) # 最適化によって算出される蓄電池の状態遷移
  @sell_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別に販売する量の配列
  @may_get_solar = 0.0 # 次の日に得られる発電量
  @yield = 0.0 # 家庭エージェントの利益
  b = (1440/TIMESTEP)
  #weight_func = -> (x) {(6.0/(2.0*(b**2)-3.0 * (b**1) + 1)) * (x-b)**2 } # 重み関数
  weight_func = -> (x) { - 2.25 / b * x + 2.25} # 重み関数
  @weights = [] # 重み関数の初期化（徐々に重みが減っていく.）
  (0..b-1).each do |index|
    @weights << weight_func.call(index) ## 重み関数
  end
 end

 # 需要量のセット
 def set_demands datas
  @demands.clear
  @demands = datas
 end

 # 太陽光発電量をセット
 def set_solars datas
  @solars=[]
  @solars = datas.map{|x| x*0.85 } # 発電効率85%
 end

 ### version 0.9 逐次的処理 ##########################################
 # 一日の行動
 def onestep_action time
   @clock[:step] = time
   @clock[:day] += 1 if (time+1) == (1440/TIMESTEP)
   self.action time
   #self.decide_sell_power #
   #self.decide_buy_power #
 end

 #=購入する電力量及び販売する電力量の決定
 # ここのメソッドにエージェントの逐次敵戦略を記述 
 # cnt: 現在のタイムステップ
 # return: simdata
 def action cnt
   pre_cnt = cnt > 0 ? cnt - 1 : (1440/TIMESTEP) - 1
   simdata = {}
   simdata[:weather] = @weather
   simdata[:battery] = @battery
   #ap smooth_train_datum(:demands)
   #ap @demands
   @pre_battery = @battery # 一つ前の蓄電量の記憶
   #ap @buy_batteries
   case @strategy # default is normal strategy
   when NORMAL_STRATEGY
     bref = estimate_bref cnt
     simdata[:demand] = @demands[cnt] #
     simdata[:solar] = @solars[cnt] #
     buy_plus = 0.0 # 足りない分の電力を余分に購入する分
     sell_plus = 0.0 # 容量を超えてしまわないように売る量を微調整
     @battery = @battery - simdata[:demand] + simdata[:solar] # 購入量と販売量考慮せずの蓄電池の更新
     @battery = 0.0 if @battery < 0.0
     @battery = @max_strage if @battery > @max_strage
     # Particleによる次の予測太陽光発電量
     next_solar = @filter.predict_next_value(simdata[:solar], cnt)
     @filter.train_per_step simdata[:solar] # 学習
     # 次の需要の推定量
     next_demand = simdata[:demand] + predict_diff(cnt, :demands)


     # 購入量と販売量の変更
     simdata[:buy] = @buy_times[cnt]
     if simdata[:buy] < 0.0
       simdata[:sell] = -1 * simdata[:buy]
       simdata[:buy] = 0.0
     else 
       simdata[:sell] = 0.0
     end

     simdata[:optimum_buy] = @buy_times[cnt] 

     if @battery + @buy_times[cnt] > @max_strage
       simdata[:buy] = @max_strage - @battery
     end

     if @battery - @sell_times[cnt] < 0.0
       simdata[:sell] = 0.0
     end

     ## 逐次戦略開始
     #if next_solar + simdata[:demand] > simdata[:solar] + next_solar  # 次の時刻と今得られた発電量と需要の比較 
     #  # 発電量が多い時
     #  if next_solar > next_demand # 次の時刻は発電量が多い
     #    if @battery + next_solar - next_demand > bref # 充電量が目標値より多い場合
     #      simdata[:sell] = @battery - bref if bref < @battery # 電力の販売
     #      simdata[:buy] = 0.0 # 購入キャンセル
     #    end
     #  else # 次の時刻は需要が多い
     #    ## 基本的には買う
     #  end
     #else # 次の時間での発電量が消費量より上回ると予測された時
     #  # 需要が多い時
     #  if next_solar > next_demand # Case 2-1:次の時刻は発電量が多い
     #    simdata[:buy] = 0.0 # 購入キャンセル
     #    simdata[:sell] = @battery - bref if bref < @battery # 電力の販売
     #  else # 次の時刻は需要が多い
     #    if @battery + next_solar - next_demand > bref # 充電量が目標値より多い場合
     #      simdata[:buy] = 0.0 # 購入キャンセル
     #      simdata[:sell] = @battery - bref if bref < @battery
     #    end
     #  end
     #end
     ### 
     simdata[:opt_battery] = @day_batteries[cnt]
     est_diff = @day_batteries[cnt] - @day_batteries[pre_cnt]
     real_diff = @battery - @pre_battery
     if est_diff > 0 and real_diff > 0 and est_diff > real_diff # 電力多く売ってる可能性
       #p "-sell-"
       #ap simdata[:sell]
       simdata[:sell] = ( real_diff / est_diff ) * simdata[:sell]
       #ap simdata[:sell]
     elsif est_diff > 0 and real_diff < 0
       #ap "--case 2"
       #ap simdata
       simdata[:sell] = 0.0
     elsif est_diff < 0 and real_diff < 0 and est_diff < real_diff # 電力多く買ってしまってる可能性
       #p "-buy-"
       #ap simdata[:buy]
       simdata[:buy] = ( real_diff / est_diff ) * simdata[:buy]
       #ap simdata[:buy]
     elsif est_diff < 0 and real_diff > 0 
       #ap "--case 4"
       #ap simdata
       #simdata[:buy] = 0.0
     end
     
     ## 逐次戦略終了 
     simdata[:sell] = MAX_TRANSMISSION if simdata[:sell] > MAX_TRANSMISSION
     simdata[:sell] = @battery if simdata[:sell] > @battery
     simdata[:buy] = MAX_TRANSMISSION if simdata[:buy] > MAX_TRANSMISSION
     simdata[:buy] = @max_strage - @battery if @battery + simdata[:buy] > @max_strage
       
     @battery = @battery + simdata[:buy] - simdata[:sell]
     #ap @battery
     simdata[:predict] = next_solar 
     simdata[:battery] = @battery
     ##### 電力事業所にメッセージング
     ap "[HOME]: 家庭が購入する#{simdata[:buy]}"
     send_message "id:#{@id},buy:#{simdata[:buy]},sell:#{simdata[:sell]}" 
   when SECOND_STRATEGY

   when THIRD_STRATEGY
   end
   @oneday_battery[@clock[:step]] = @battery # @clockを使うのはプログラムの統一性を図るため
   @simdatas << simdata
   return simdata
 end

 # 時刻tにおける充電目標値を見積る
 #
 def estimate_bref t
   #batterys = smooth_train_datum :battery
   demands = smooth_train_datum :demands
   solars = smooth_train_datum :solars
   bref = demands[t] - solars[t]
   return bref > 0.0 ? bref : 0.0
 end

 #### 一日始まるときに行動する内容 ####################################33
 def day_start_action
   time = Time.now
   ap "最適化開始 --"
   @buy_times, @day_batteries = optimum_oneday
   #ap @day_batteries
   #@buy_times, @sell_times = optimum_oneday
   ap "最適化終了 -- 経過時間 #{(Time.now - time)/60.0}mins"
 end

 ##
 # 一日の最適化問題を解くメソッド
 def optimum_oneday
   demands = self.smooth_demand_train_data
   solars = self.smooth_solar_train_data
   #buys = self.smooth_buy_train_data
   #sells = self.smooth_sell_train_data 
   purchase_prices = self.smooth_p_purchase_price
   #buy_prices = self.smooth_trains_datum :p_buy_price
   sell_prices = self.smooth_p_sell_price
   #battery = self.smooth_battery_train_data
   # DifferentialEvolution用の初期パラメータ設定
   params = {
     step: TIMESTEP,
     purchase_prices: purchase_prices,
     sell_prices: sell_prices,
     battery: @battery,
     demands: demands,
     solars: solars,
     max_strage: @max_strage
   }
   #ap @battery
   df = DifferentialEvolution::instance params 
   # configuration
   #search_space = Array.new((1440/TIMESTEP)*2,Array.new([0,500]))
   search_space = Array.new((1440/TIMESTEP)*2,Array.new([-500,500*0.9])) # マイナスはsell値
   problem_size = search_space.size
   pop_size = POP_SIZE_BASE * problem_size
   best = df.search(MAX_GENS, search_space, pop_size, WEIGHTF, CROSSF)
   #ap best
   
   #buys = best[:vector][0...(1440/TIMESTEP)]
   buys = best[:vector][0...(1440/TIMESTEP)].map.with_index{|m,time| df.call_amount_buy(time,m) }
   #batteries = best[:vector][(1440/TIMESTEP)...best[:vector].size]
   batteries = best[:battery]
   #sells = best[:vector][(1440/TIMESTEP)...2*(1440/TIMESTEP)]
   return [buys, batteries]
 end

 #####################################################################
 
 # 時間をすすめる
 def next_time time
  #@clock += 1
 end

 # 1日の初期化
 def init_date
  #@clock = 0
  self.csv_out
  @filter.particles_zero unless @filter.nil?
  train_data_per_day
  ## 学習時に用いる一時退避用の配列初期化
  @buy_times = Array.new((1440/TIMESTEP),0.0) 
  @sell_times = Array.new((1440/TIMESTEP),0.0)
  @oneday_buys = Array.new((1440/TIMESTEP), 0.0) # 一日の買った電力をタイプステップごとで記録し学習
  @oneday_sells = Array.new((1440/TIMESTEP), 0.0) # 一日の売った電力をタイムステップごとで記録し学習
  @oneday_battery = Array.new((1440/TIMESTEP), 0.0) 
  #@filter.init_data if !@filter.nil? && !@filter.eql?("normal")
 end

 ## 
 # 学習データの平均的データを取得
 # tag: ハッシュタグ
 def smooth_train_datum tag
   trains = @trains[tag][@weather]
   chunk = trains.size / (1440/TIMESTEP)
   results = Array.new((1440/TIMESTEP),0.0)
   return results if chunk == 0
   (0...(1440/TIMESTEP)).each do |cnt|
     sum = 0.0
     for i in 0...chunk
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     results[cnt] = (sum / chunk.to_f)
   end
   return results
 end

 ##
 # 需要の学習データから平均的な一日の需要データを取得
 def smooth_demand_train_data
   demand_trains = @trains[:demands][@weather]
   chunk = demand_trains.size/(1440/TIMESTEP)
   result = Array.new((1440/TIMESTEP),0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += demand_trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ##
 # 発電量の学習データから平均的な一日の需要データを取得
 def smooth_solar_train_data
   solar_trains = @trains[:solars][@weather]
   chunk = solar_trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += solar_trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_buy_train_data
   trains = @trains[:buys][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_sell_train_data
   sells = @trains[:sells][@weather]
   chunk = sells.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += sells[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_p_purchase_price
   trains = @trains[:p_purchase_price][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result

 end

 ##
 #
 def smooth_p_sell_price
   trains = @trains[:p_sell_price][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 def smooth_battery_train_data
   trains = @trains[:battery][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end
 
 
 #####
 # 天気予報のチェック
 #  ある１位日の総発電量から天候をセットする
 #  - sum_solar: ある一日の総発電量 
 def switch_weather_for_pf sum_solar
  @filter.eval_weather sum_solar if !@filter.nil?
  if SUNNY_BORDER < sum_solar
   @weather = SUNNY
  elsif CLOUDY_BORDER < sum_solar
   @weather = CLOUDY
  else
   @weather = RAINY
  end
  ####
  #### select_time_and_value_to_buy # 夜間におよその購入量と蓄電量を概算する 
 end

 ###
 # recieve_msg
 # @msg: メッセージ
 def recieve_msg msg
   ds = msg.split(",")
   reply_to = ds[0].gsub("id:","")
   sell = 0.0
   buy = 0.0
   ds.each do |pay|
     case pay
     when /^buy:.*/
       sell = pay.gsub('buy:','').to_f ## buyは電力会社が買った量
     when /^sell:.*/
       buy = pay.gsub('sell:','').to_f ## sellは電力会社が売った量
     end
   end
   solar = @solars[@clock[:step]]
   demand = @demands[@clock[:step]]
   #ap @battery
   self.update_battery sell,buy,demand,solar
   @oneday_buys[@clock[:step]] = buy
   @oneday_sells[@clock[:step]] = sell
 end

 ## 
 # 10日周期で保存
 def csv_out
   cnt = @clock[:day] + 1
   if cnt % 10 == 0
     filepath = "#{File.expand_path File.dirname __FILE__}/../result/#{@id}/result_#{cnt}.csv"
     file = open(filepath,'w')
     file.write("buy,battery,predict,real,sell,weather,demand,optimum,opt_battery\n")
     @simdatas.each {|data|
       file.write "#{data[:buy]},#{data[:battery]},#{data[:predict]},#{data[:solar]},#{data[:sell]},#{data[:weather]},#{data[:demand]},#{data[:optimum_buy]},#{data[:opt_battery]}\n"
     }
     file.close
     @simdatas = []
   end
 end

 ### バッテリー更新
 def update_battery sell, buy, demand, solar
   @penalty = 0.0
   @battery = @battery - sell - demand + solar + buy
   if @battery < 0.0
     @penalty = (@battery.abs * PENALTY)
     @battery = 0.0
   elsif @battery > @max_strage
     @penalty = (@max_strage - @battery).abs * PENALTY
     @battery = @max_strage
   end
 end

 private

 #####
 # chunk分に学習していく
 #
 def train_data_per_day
  @trains[:demands][@weather].concat @demands.clone
  @trains[:solars][@weather].concat @solars.clone
  @trains[:buys][@weather].concat @oneday_buys.clone
  @trains[:sells][@weather].concat @oneday_sells.clone
  @trains[:battery][@weather].concat @oneday_battery.clone

  if @chunk_size * (1440/TIMESTEP) < @trains[:demands][@weather].size
   @trains[:demands][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:solars][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:buys][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:sells][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:battery][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
  end

  ## 価格のデータを学習
  ppp = []
  psp = []
  @my_contractor.trains[@weather].each do |data|
    psp << data[:sell_price]
    ppp << data[:purchase_price]
  end

  @trains[:p_purchase_price][@weather].concat ppp.clone ## こいつのデータはどんどん肥大
  @trains[:p_sell_price][@weather].concat psp.clone ## こいつのデータはどんどん肥大
  if @chunk_size * (1440/TIMESTEP) < @trains[:p_purchase_price][@weather].size
    @trains[:p_purchase_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
    @trains[:p_sell_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
  end
 end

 #####
 # 朝5時に発動する
 def get_trains_power_average_from_time time
  sum_power = 0.0
  size = 15 * (60/TIMESTEP) - 1
  if time < 15*(60/TIMESTEP) && @trains[:solars][@weather].size > 0
   for index in time..size
    demand = @trains[:demands][@weather][index]
    solar = @trains[:solars][@weather][index]
    sum_power = sum_power + solar - demand
   end
   return sum_power
  end
  return 0.0
 end

 # フィルターの初期化
 def filter_init type
  case type
  when 'pf'
   return @filter = ParticleFilter.new 
  when 'normal'
   return @filter = 'normal'
  when 'none'
   return nil
  end
  return nil
 end
 #################### RabbitMQ ###########################
 # Bunnyを用いてRabbitMQによるメッセージング通信
 
 # メッセージを送る
 def send_msg msg
   @reply_q.publish msg
 end

 # キューの受付準備
 def ready_box
   @my_q.subscribe(:exclusive => true, :ack => true) do |delivery_info, properties, payload|
     self.recieve_msg "#{payload}"
     #puts "Received #{payload}, message properties are #{properties.inspect}"
   end
 end
 #########################################################

 ## msgの送信
 def send_message msg
  @my_contractor.recieve_msg msg
 end

 ##
 # ステップとtime、天候が等しい学習データを検索
 # @time: step
 def search_q_trains time
   @trains[:q_trains].select{|x| x[:step] == time && x[:weather] == @weather }
 end

 #  ある時刻における変化量の平均を取得
 #  過去chunk_size日分のデータを利用
 #  ※ tからt+1の変化量の平均を取得
 #
 #  time: 現在時刻
 #  tag: 学習データのキー(demand, solar, battery, ...)
 #  return 変化量の平均
 def predict_diff time, tag
   trains = @trains[tag][@weather]
   return 0.0 if trains.empty?
   chunk = trains.size / (1440/TIMESTEP)
   ## 時間ステップの最後尾は次の時間は0番目とする
   next_time = time < (1440/TIMESTEP)-1 ? time + 1 : 0
   result = (0...chunk).inject(0.0){|acc,i|
     plus_index = i * (1440/TIMESTEP)
     acc += trains[next_time+plus_index] - trains[time+plus_index]
   }
   return result / @chunk_size
 end

end
