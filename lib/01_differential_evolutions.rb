# coding: utf-8
require 'awesome_print'

module DifferentialEvolution


  ## 起動
  def instance parameters
    Core.new parameters
  end
  
  module_function :instance

  ### class
  class Core
    attr_accessor :step, :purchase_prices, :sell_prices, :search
    PENALTY_PRICE=30 ## 基本は最大販売価格
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
      @battery = parameters[:battery] # 過去何日間分の蓄電量のステップごとの平均
      @max_strage = parameters[:max_strage] # バッテリーの最大容量
      @demands = parameters[:demands] # 過去何日間分の需要のステップごとの平均
      @solars = parameters[:solars] # 過去何日間分の発電量のステップごとの平均
    end

    ## 評価関数
    # 説明： 
    # ２つ先の状態を見て増えそうなら売る、減りそうなら買う
    # 評価関数も減る場合には買う時と売る時でコスト計算を場合分けする
    #  1: 2つ先でバッテリーが減っている場合
    #    a) 購入した時コストが下がる（最適に近い
    #    b) 販売した時コストが上がる（最適に遠ざかる
    #  2: 2つ先でバッテリーが増えている場合
    #    a) 購入した時コスト増
    #    b) 販売した時コスト減
    def objective_function(vector)
      buy_powers = vector[0...@step]
      sell_powers = vector[@step...@step*2]
      cost1 = 0.0
      cost2 = 0.0
      penalty_cost = 0.0
      (0...@step).each{|index|
        buy = buy_powers[index]
        sell = sell_powers[index]
        b1 = @battery[index]
        b2 = b1
        next_battery = @battery[index] - @demands[index] + @solars[index] # 次のバッテリーの状態
        ## 蓄電池容量の制約によるペナルティ計算
        if next_battery + buy > @max_strage
          penalty_cost += (next_battery + buy - @max_strage)*PENALTY_PRICE # 電力を超過してしまう分追加
        elsif next_battery - sell < 0.0
          penalty_cost += (next_battery - sell).abs * PENALTY_PRICE # マイナス分コストペナルティ追加
        end
        # 2つ先状態から買う買わないの決定
        if index < @step - 2
          b2 = @battery[index+2]
        elsif index == @step - 2 # 現在の添字がブービー 
          b2 = @battery[0] 
        else # 現在の添字が最後
          b2 = @battery[1]
        end
        #
        if b1 > b2
          cost1 -= @sell_prices[index] * buy
          cost2 += @purchase_prices[index] * sell
        else
          cost1 += @sell_prices[index] * buy
          cost2 -= @purchase_prices[index] * sell
        end
      }
      cost = cost1 + cost2 + penalty_cost
      return cost
    end

    ## 特徴ベクトルの生成
    def create_vector(minmax)
      return Array.new(minmax.size) do |i|
        minmax[i][0] + ((minmax[i][1] - minmax[i][0]) * rand())
      end
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

    def create_children(pop, minmax, f, cr)
      children = []
      pop.each_with_index do |p0, i|
        p1, p2, p3 = select_parents(pop, i)
        children << de_rand_1_bin(p0, pop[p1], pop[p2], pop[p3], f, cr, minmax)
      end
      return children
    end

    def select_population(parents, children)
      return Array.new(parents.size) do |i|
        (children[i][:cost]<=parents[i][:cost]) ? children[i] : parents[i]
      end
    end

    def search(max_gens, search_space, pop_size, f, cr)
      pop = Array.new(pop_size) {|i| {:vector=>create_vector(search_space)}}
      pop.each{|c| c[:cost] = objective_function(c[:vector])}
      best = pop.sort{|x,y| x[:cost] <=> y[:cost]}.first
      max_gens.times do |gen|
        children = create_children(pop, search_space, f, cr)
        children.each{|c| c[:cost] = objective_function(c[:vector])}
        pop = select_population(pop, children)
        pop.sort!{|x,y| x[:cost] <=> y[:cost]} # コスト最小順に並べる
        best = pop.first if pop.first[:cost] < best[:cost]
        #puts " > gen #{gen+1}, fitness=#{best[:cost]}"
      end
      return best
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
=begin
if __FILE__ == $0
  # problem configuration
  #search_space = [[0,500],[0,500],[30,30],[30,30],[85,85],[0.0,0.0],[80.0,80.0],[0.0,0.0],[68.0,68.0]]
  file = open("test_result.csv","w")
  (0...10).each do |count|
    search_space = Array.new(96*2,Array.new([0,500]))
    problem_size = search_space.size
    # algorithm configuration
    max_gens = 200
    pop_size = 10 * problem_size
    weightf = 0.8
    crossf = 0.9
    # execute the algorithm
    max_strage = 5000.0
    demands = open("./test_demand.csv",'r').readline.split(',').map{|data| data.to_f}
    solars = open("./test_solar.csv",'r').readline.split(',').map{|data| data.to_f}
    purchases = open("./test_purchase.csv",'r').readline.split(",").map{|data| data.to_f}
    sells = open("./test_sell.csv",'r').readline.split(",").map{|data| data.to_f}
    battery = open("./test_battery.csv", 'r').readline.split(",").map{|data| data.to_f}
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

    #best = DifferentialEvolution::search(max_gens, search_space, pop_size, weightf, crossf)
    #best = DifferentialEvolution::search_buys_or_sells(max_gens, search_space, pop_size, weightf, crossf, other_parameters)
    #best = DifferentialEvolution::search_buy_and_sell(max_gens, search_space, pop_size, weightf, crossf)
    #ap best
    buy_powers = best[:vector][0...96]
    sell_powers = best[:vector][96...96*2]
    file.write "#{buy_powers.join(",")}\n#{sell_powers.join(",")}\n#{sells.join(",")}\n#{purchases.join(",")}\n\n"
  end
  file.close
  #puts "done! Solution: f=#{best[:cost]}, s=#{best[:vector].inspect}"
end
=end
