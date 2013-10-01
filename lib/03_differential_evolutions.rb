# coding: utf-8
require 'awesome_print'

module DifferentialEvolution
  # インスタンス化
  def instance parameters
    Core.new parameters
  end
  
  module_function :instance

  ### class
  class Core
    attr_accessor :step, :purchase_prices, :sell_prices, :search, :call_amount_buy
    PENALTY_PRICE=30 ## 基本は最大販売価格
    TRANSMISSION=500.0
    # Constructor
    # parameters: { 
    #   step: Timesteps, 
    #   sell_prices: [電力の売値配列], 
    #   purchase_prices: [電力の買取価格], 
    #   battery: [バッテリ] 
    #  }
    def initialize parameters
      @step =  parameters[:step] # 一日のステップ数
      @purchase_prices = parameters[:purchase_prices] # 買取価格
      @sell_prices = parameters[:sell_prices] # 販売価格
      @battery = parameters[:battery] # 時刻0でのバッテリーの蓄電量
      @max_strage = parameters[:max_strage] # バッテリーの最大容量
      @demands = parameters[:demands] # 過去何日間分の需要のステップごとの平均
      @solars = parameters[:solars] # 過去何日間分の発電量のステップごとの平均
    end

    # 蓄電池へのチャージ量から購入量に変換
    def call_amount_buy time, discharge
      result =  @demands[time] - @solars[time] - discharge
      if result > TRANSMISSION
        TRANSMISSION
      elsif result < -1 * TRANSMISSION
        -1 * TRANSMISSION
      else
        result
      end
    end

    #=時間制約付きオブジェクトファンクション
    # vector: [0]: b+, [1]: b-, [2]: battery
    def objective_function(vector)
      cost = 0.0
      pre_buy = 0.0 # 前の購入量を覚えておく
      charges = vector[0...(1440/@step)]
      buys = vector[(1440/@step)...(1440/@step)*2]
      sum = 0.0
      charges.each_with_index do |value,time| # value: 放電量, time: 時間
        pre_time = time == 0 ? charges.size - 1 : time - 1
        #if diff >= 0
        buy = buys[time]
        u = @solars[time] + value + buy
        #alpha = 120.0
        #cost += @sell_prices[time] * (diff + value)**2 + alpha * (buy - pre_buy)**2
        if buy > 0.0
          cost += (@demands[time] - u)**2 + @sell_prices[time] * buy
          #cost += @purchase_prices[pre_time] * (diff_2 + value) ** 2
        else
          cost += (@demands[time] - u) ** 2 
          #cost += @sell_prices[pre_time] * (diff_2 + value) ** 2 
        end

        pre_buy = buy # 前の時刻の購入量を記憶する
        sum += buy
      end

      return cost, sum
    end

    ## 特徴ベクトルの生成
    #def create_vector(minmax)
    #  return Array.new(minmax.size) do |i|
    #    minmax[i][0] + ((minmax[i][1] - minmax[i][0]) * rand())
    #  end
    #end

    #=制約条件が時間別で変わるようにベクトルを作成する
    # 蓄電量（及び放電量）を乱数で与える
    # minmax: 最大最小の制約の初期値（動的に変更される）
    # battery: 一日の始まるときの蓄電量
    # プログラムの中身の変数：
    #  value: 蓄電池に蓄電する量(マイナスは放電する量)
    def create_vector(minmax, battery)
      size = minmax.size
      vectors = []
      batteries = []
      (0...size).each do |i|
        if i < (1440/@step)
          diff = @max_strage - battery # 蓄電池の空き容量
          surplus = @solars[i] - @demands[i]
          #surplus = @solars[i] - @demands[i]
          # 蓄電池に空きがないのに余剰電力を蓄電しようとするのを阻止
          minmax[i][1] = battery
          minmax[i][1] = TRANSMISSION * 0.9 if minmax[i][1] > TRANSMISSION * 0.9 # 最大値更新
          minmax[i][0] = diff * -1 # 蓄電
          minmax[i][0] = -1 * TRANSMISSION if minmax[i][0].abs > TRANSMISSION

          #if surplus > 0.0 then # 余剰電力があるのに儲けるな
          #  minmax[i][0] = 0.0
          #end
          if surplus > 0.0
            minmax[i][1] = 0.0 
          end
          
          # 限界値を超えないようにする(放電量)
          discharge = minmax[i][0] + ((minmax[i][1] - minmax[i][0]) * rand()) # チャージ量(蓄電池に蓄電する量)
          batteries << battery # バッテリ情報記憶
          battery -= discharge # バッテリーの更新
          vectors << discharge
        else
          value = minmax[i][0] + ((minmax[i][1] - minmax[i][0]) * rand()) # チャージ量(蓄電池に蓄電する量)
          vectors << value
        end
      end
      #ap minmax
      {vector: vectors, battery: batteries, search_space: minmax}
    end

    def de_rand_1_bin(p0, p1, p2, p3, f, cr, search_space)
      sample = {:vector=>Array.new(p0[:vector].size)}
      cut = rand(sample[:vector].size-1) + 1
      sample[:vector].each_index do |i|
        sample[:vector][i] = p0[:vector][i]
        if (i==cut or rand() < cr)
          v = p3[:vector][i] + f * (p1[:vector][i] - p2[:vector][i])
          v = search_space[i][0] if v < search_space[i][0]
          v = search_space[i][1] if v > search_space[i][1]
          sample[:vector][i] = v
        end
      end
      return sample
    end

    def select_parents(pop, current)
      p1, p2, p3 = rand(pop.size), rand(pop.size), rand(pop.size)
      p1 = rand(pop.size) until p1 != current
      p2 = rand(pop.size) until p2 != current and p2 != p1
      p3 = rand(pop.size) until p3 != current and p3 != p1 and p3 != p2
      return [p1,p2,p3]
    end

    def create_children(pop, minmaxs, f, cr)
      children = []
      pop.each_with_index do |p0, i|
        p1, p2, p3 = select_parents(pop, i)
        children << de_rand_1_bin(p0, pop[p1], pop[p2], pop[p3], f, cr, minmaxs[i])
      end
      return children
    end

    def select_population(parents, children)
      return Array.new(parents.size) do |i|
        (children[i][:cost]<=parents[i][:cost]) ? children[i] : parents[i]
      end
    end

    def search(max_gens, search_space, pop_size, f, cr)
      pop = Array.new(pop_size) {|i| create_vector(search_space, @battery)}
      #pop = Array.new(pop_size) {|i| {:vector=>create_vector(search_space, @battery)}}
      pop.each{|c| c[:cost],c[:sum] = objective_function(c[:vector])}
      best = pop.sort{|x,y| x[:cost] <=> y[:cost]}.first
      minmaxs = pop.map{|x| x[:search_space]}
      max_gens.times do |gen|
        children = create_children(pop, minmaxs, f, cr)
        children.each{|c| c[:cost], c[:sum] = objective_function(c[:vector])}
        pop = select_population(pop, children)
        pop.sort!{|x,y| x[:cost] <=> y[:cost]} # コスト最小順に並べる
        best = pop.first if pop.first[:cost] < best[:cost]
        puts " > gen #{gen+1}, fitness=#{best[:cost]}, sum_buy=#{best[:sum]}"
        #puts " cost: > #{best[:sum]}, #{best[:battery]}"
      end
      best[:battery] = return_batteries best[:vector],@battery
      best[:sum] = sum_check best[:vector][0...(1440/@step)]
      best[:vector] = best[:vector][0...(1440/@step)]

      return best
    end

    def return_batteries vector,battery
      vector.map{|x| battery += x }
    end

    def sum_check vector
      vector.each_with_index.inject(0.0){|acc, (x,time)| acc += @demands[time] - @solars[time] + x }
    end

    def search_buy_and_sell max_gens, search_space, pop_size, weightf, crossf
      result = {}
      best = self.search( max_gens, search_space, pop_size, weightf, crossf)
      result = {buy: best[:vector][0], sell: best[:vector][1]}
      return result
    end
  end

end

## test
#=begin
if __FILE__ == $0
  # problem configuration
  #search_space = [[0,500],[0,500],[30,30],[30,30],[85,85],[0.0,0.0],[80.0,80.0],[0.0,0.0],[68.0,68.0]]
  file = open("test_result.csv","w")
  (0...10).each do |count|
    search_space = Array.new(96,Array.new([-500.0,500.0]))
    problem_size = search_space.size
    print "1:: \n"
    # algorithm configuration
    max_gens = 100
    #max_gens = 200
    pop_size = 10 * problem_size
    weightf = 0.8 # ベクトルのステップサイズ
    crossf = 0.9 # 多いか少ないかの判定
    # execute the algorithm
    max_strage = 5000.0
    demands = open("./test_demand.csv",'r').readline.split(',').map{|data| data.to_f}
    solars = open("./test_solar.csv",'r').readline.split(',').map{|data| data.to_f}
    purchases = open("./test_purchase.csv",'r').readline.split(",").map{|data| data.to_f}
    sells = open("./test_sell.csv",'r').readline.split(",").map{|data| data.to_f}
    #battery = open("./test_battery.csv", 'r').readline.split(",").map{|data| data.to_f}
    battery = 2200.0
    params = {
      purchase_prices: purchases, 
      sell_prices: sells,
      step: 96,
      battery: battery,
      demands: demands,
      solars: solars,
      max_strage: max_strage
    }
    df = DifferentialEvolution::instance params
    best = df.search(max_gens, search_space, pop_size, weightf, crossf)
    ap best[:sum]

    #best = DifferentialEvolution::search(max_gens, search_space, pop_size, weightf, crossf)
    #ap best
    buy_powers = best[:vector].map.with_index{|x,time| df.call_amount_buy(time,x) }
    #sell_powers = best[:vector][96...96*2]
    file.write "#{buy_powers.join(",")}\n#{sells.join(",")}\n#{purchases.join(",")}\n\n"
    #file.write "#{buy_powers.join(",")}\n#{sell_powers.join(",")}\n#{sells.join(",")}\n#{purchases.join(",")}\n\n"
  end
  file.close
  #puts "done! Solution: f=#{best[:cost]}, s=#{best[:vector].inspect}"
end
#=end
