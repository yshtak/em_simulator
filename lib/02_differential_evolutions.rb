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
      #@purchase_prices = parameters[:purchase_prices] # 買取価格
      @sell_prices = parameters[:sell_prices] # 販売価格
      @battery = parameters[:battery] # 過去何日間分の蓄電量のステップごとの平均
      @max_strage = parameters[:max_strage] # バッテリーの最大容量
      @demands = parameters[:demands] # 過去何日間分の需要のステップごとの平均
      @solars = parameters[:solars] # 過去何日間分の発電量のステップごとの平均
    end

    ## 評価関数
    # 説明：
    # 2つ先の状態を見て増えそうなら売る、減りそうなら買う.
    # また，蓄電容量を超えようとしたり，蓄電量が0以下になりそうなときは
    # ペナルティを加えて，評価を下げる．
    #
    # 評価関数も減る場合には買う時と売る時でコスト計算を場合分けする
    #  1: 2つ先でバッテリーが減っている場合
    #    a) 購入した時コストが下がる（最適に近い
    #    b) 販売した時コストが上がる（最適に遠ざかる
    #  2: 2つ先でバッテリーが増えている場合
    #    a) 購入した時コスト増
    #    b) 販売した時コスト減
    # 
    #  [ペナルティについて] 
    #    ペナルティは蓄電容量を超えるまたは下回る現象が起きた時に発生する
    #    1, 買い過ぎで蓄電容量を超えそうなとき
    #    2, 売りすぎて蓄電量が0以下になりそう
    #
    def objective_function(vector)
      buy_powers = vector[0...@step]
      cost = 0.0
      (0...@step).each{|index|
        buy0 = index > 0 ? buy_powers[index-1] : buy_powers.last
        buy1 = buy_powers[index]
        a = (@demands[index] - @solars[index] - buy1)**2 * @sell_prices[index]  
        b =  (buy1 - buy0)**2
        cost += a + b
      }
      #cost = cost1 + cost2 + penalty_cost
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
        puts " > gen #{gen+1}, fitness=#{best[:cost]}"
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
#=begin
if __FILE__ == $0
  # problem configuration
  #search_space = [[0,500],[0,500],[30,30],[30,30],[85,85],[0.0,0.0],[80.0,80.0],[0.0,0.0],[68.0,68.0]]
  file = open("test_result.csv","w")
  (0...10).each do |count|
    search_space = Array.new(96,Array.new([0,500]))
    problem_size = search_space.size
    print "1:: \n"
    # algorithm configuration
    max_gens = 10
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
    #ap best
    buy_powers = best[:vector][0...96]
    #sell_powers = best[:vector][96...96*2]
    file.write "#{buy_powers.join(",")}\n#{sells.join(",")}\n#{purchases.join(",")}\n\n"
    #file.write "#{buy_powers.join(",")}\n#{sell_powers.join(",")}\n#{sells.join(",")}\n#{purchases.join(",")}\n\n"
  end
  file.close
  #puts "done! Solution: f=#{best[:cost]}, s=#{best[:vector].inspect}"
end
#=end
