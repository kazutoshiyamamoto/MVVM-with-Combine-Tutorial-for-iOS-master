/// Copyright (c) 2019 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import SwiftUI
import Combine

// ObservableObject:WeeklyWeatherViewModelのプロパティをバインディングとして使用できることを意味する
class WeeklyWeatherViewModel: ObservableObject {
  
  // @Published修飾子でプロパティを監視
  @Published var city: String = ""
  @Published var todaysWeatherEmoji: String = ""
  @Published var dataSource: [DailyWeatherRowViewModel] = []
  
  private let weatherFetcher: WeatherFetchable
  private var disposables = [AnyCancellable]()
  
  init(
    weatherFetcher: WeatherFetchable,
    scheduler: DispatchQueue = DispatchQueue(label: "WeatherViewModel")
  ) {
    self.weatherFetcher = weatherFetcher
    
    // https://developer.apple.com/documentation/combine/passthroughsubject
    // PassthroughSubject:SubjectsはPublisherとSubscriberの間のような存在で複数のSubscriberに値を出力できる。PassthroughSubjectはSubjectsの一種で値を保持せずに来たものをそのまま出力する。
    // https://qiita.com/shiz/items/5efac86479db77a52ccc
    let _fetchWeather = PassthroughSubject<String, Never>()
    
    $city
      // filter:cityが空でないことを返す（空でないものをフィルターする）=空チェック？
      .filter { !$0.isEmpty }
      // debounceは、前回のイベント発生後から一定時間内に同じイベントが発生するごとに処理の実行を一定時間遅延させ、一定時間イベントが発生しなければ処理を実行するという挙動。https://qiita.com/marty-suzuki/items/496f211e22cad1f8de19
      // TextFieldでの文字入力の時間を考慮？（不必要にリクエストさせない対策？）
      .debounce(for: .seconds(0.5), scheduler: scheduler)
      // cityの値を購読（View側でTextFieldに文字が入力されると発火するようになる？）
      // _fetchWeather.send($0):cityの値が変化したことを通知されるとその値をサブスクライバー（_fetchWeather？）に送信する？
      .sink(receiveValue: { _fetchWeather.send($0) })
      // disposablesは、リクエストへの参照のコレクションと考える。 これらの参照を保持しないと、送信するネットワークリクエストは保持されず、サーバーからの応答を取得できなくなる。
      .store(in: &disposables)
    
    // cityは引数
    _fetchWeather
      .map { city -> AnyPublisher<Result<[DailyWeatherRowViewModel], WeatherError>, Never> in
        // 週間天気を取得
        weatherFetcher.weeklyWeatherForecast(forCity: city)
          .prefix(1)
          // 成功時
          // 提供されたクロージャーで上流パブリッシャーからのすべての要素を変換
          // https://developer.apple.com/documentation/combine/passthroughsubject/map(_:)-77nj3
          .map {
            Result.success(
              Array.removeDuplicates(
                $0.list.map(DailyWeatherRowViewModel.init)
              )
            )
        }
          // 失敗時
          // https://developer.apple.com/documentation/combine/publishers/catch
          // Justはエラーを発行できないが、catchを設定することでデフォルトメッセージを返せる（エラーを吐く役割として使える）
          .catch { Just(Result.failure($0)) }
          .eraseToAnyPublisher()
    }
      // 複数の上流パブリッシャーからのイベントストリームをフラット化して、それらが単一のイベントストリームからのものであるかのように見せる
      // https://developer.apple.com/documentation/combine/future/switchtolatest()-2mp1
      .switchToLatest()
      // receiveが定義された後の処理をメインスレッドで実行する
      // https://qiita.com/shiz/items/9dc8e9a96f399b6c7246
      .receive(on: DispatchQueue.main)
      // sink:Publisherから受け取った値を引数にしたクロージャを受け取る
      // https://qiita.com/shiz/items/5efac86479db77a52ccc
      .sink(receiveValue: { [weak self] result in
        guard let self = self else { return }
        switch result {
        case let .success(forecast):
          self.dataSource = forecast
          self.todaysWeatherEmoji = forecast.first?.emoji ?? ""
          
        case .failure:
          self.dataSource = []
          self.todaysWeatherEmoji = ""
        }
      })
      .store(in: &disposables)
    
    // ここまでがinit
  }
}

extension WeeklyWeatherViewModel {
  var currentWeatherView: some View {
    return WeeklyWeatherBuilder.makeCurrentWeatherView(
      withCity: city,
      weatherFetcher: weatherFetcher
    )
  }
}
