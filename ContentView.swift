import SwiftUI

// 应用入口
@main
struct QuoteApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

// 主标签视图
struct MainTabView: View {
    @StateObject private var quoteManager = QuoteManager()
    
    var body: some View {
        TabView {
            HomeView(quoteManager: quoteManager)
                .tabItem {
                    Image(systemName: "house")
                    Text("首页")
                }
            
            AboutView()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text("关于")
                }
        }
    }
}

// 首页视图 - 修复UI刷新问题
struct HomeView: View {
    let quoteManager: QuoteManager
    @State private var showingCategories = false
    // 修复：添加var关键字
    @State private var refreshTrigger: UUID = UUID()
    
    var body: some View {
        VStack {
            // 顶部导航栏
            HStack {
                Button(action: {
                    showingCategories = true
                    print("分类菜单打开 - 可用分类数: \(quoteManager.categories.count)")
                }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title)
                }
                .padding(.leading)
                
                Text("原批语录")
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                
                Spacer()
                    .frame(width: 40)
                    .padding(.trailing)
            }
            .frame(height: 60)
            
            // 语录显示区域 - 添加使用id确保刷新
            Text(quoteManager.currentQuote)
                .id(refreshTrigger) // 关键修复：使用唯一唯一ID触发刷新
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(quoteManager.hasData ? Color(.systemGray6) : Color(.systemRed).opacity(0.1))
                .cornerRadius(12)
                .padding()
                .allowsHitTesting(false)
                .foregroundColor(quoteManager.hasData ? .primary : .red)
                .animation(.easeInOut, value: quoteManager.currentQuote) // 添加过渡动画
                
            // 下一条按钮 - 点击时更新触发器
            Button(action: {
                quoteManager.nextQuote()
                // 触发UI刷新
                refreshTrigger = UUID()
            }) {
                Text("下一条")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(quoteManager.hasData ? Color.blue : Color.gray)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .disabled(!quoteManager.hasData)
            
            // 状态提示栏
            if !quoteManager.hasData {
                Text("数据加载异常: 请检查quotes.txt文件")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.bottom)
            } else {
                // 修复：修正字符串插值语法
                Text("当前分类: \(quoteManager.currentCategory ?? "全部")")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom)
            }
        }
        .sheet(isPresented: $showingCategories) {
            // 修复：添加parentRefreshTrigger参数
            CategoryView(quoteManager: quoteManager, isPresented: $showingCategories, parentRefreshTrigger: $refreshTrigger)
                .modifier(SheetModifier())
        }
    }
}

// 分类选择视图 - 修复分类选择后不刷新问题
struct CategoryView: View {
    let quoteManager: QuoteManager
    @Binding var isPresented: Bool
    // 引用首页的刷新触发器
    @Binding var parentRefreshTrigger: UUID
    
    init(quoteManager: QuoteManager, isPresented: Binding<Bool>, parentRefreshTrigger: Binding<UUID>) {
        self.quoteManager = quoteManager
        self._isPresented = isPresented
        self._parentRefreshTrigger = parentRefreshTrigger
    }
    
    var body: some View {
        NavigationView {
            if quoteManager.categories.isEmpty {
                Text("没有找到任何分类\n请检查quotes.txt格式")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
                    .navigationTitle("选择分类")
                    .navigationBarItems(trailing: Button("关闭") {
                        isPresented = false
                    })
            } else {
                List(quoteManager.categories, id: \.self) { category in
                    Button(action: {
                        quoteManager.filterQuotes(by: category)
                        // 切换分类后触发刷新
                        parentRefreshTrigger = UUID()
                        isPresented = false
                    }) {
                        HStack {
                            Text(category)
                            Spacer()
                            Text("\(quoteManager.quoteCount(for: category))条")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .navigationTitle("选择分类")
                .navigationBarItems(trailing: Button("关闭") {
                    isPresented = false
                })
            }
        }
    }
}

// 关于页面
struct AboutView: View {
    var body: some View {
        VStack {
            Image("OP")
                .resizable()
                .scaledToFit()
                .frame(width: 474, height: 496)
                .foregroundColor(.red)
                .padding()
            
            Spacer()
            
            Text("原批语录©️JIU-F 2025 QQ:2761643939")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding()
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 语录管理类 - 确保@Published属性正确触发
class QuoteManager: ObservableObject {
    @Published var currentQuote: String = "加载中..."
    @Published var categories: [String] = []
    @Published var hasData: Bool = false
    var currentCategory: String?
    private var allQuotes: [String: [String]] = [:]
    private var currentIndex: Int = 0
    
    init() {
        loadQuotes()
        selectRandomQuote()
    }
    
    func quoteCount(for category: String) -> Int {
        allQuotes[category]?.count ?? 0
    }
    
    private func loadQuotes() {
        guard let url = Bundle.main.url(forResource: "quotes", withExtension: "txt") else {
            currentQuote = "错误：找不到quotes.txt文件"
            print("❌ 关键错误：在项目资源中找不到quotes.txt，请确保文件已添加")
            hasData = false
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            parseQuotes(content)
            
            let totalQuotes = allQuotes.values.map { $0.count }.reduce(0, +)
            if categories.isEmpty || totalQuotes == 0 {
                currentQuote = "错误：语录文件格式不正确"
                print("❌ 解析错误：找到\(categories.count)个分类，但总语录数为0")
                hasData = false
            } else {
                print("✅ 加载成功：\(categories.count)个分类，共\(totalQuotes)条语录")
                hasData = true
            }
        } catch {
            currentQuote = "加载失败：\(error.localizedDescription)"
            print("❌ 读取错误：\(error)")
            hasData = false
        }
    }
    
    private func parseQuotes(_ content: String) {
        var currentCategory: String?
        allQuotes.removeAll()
        categories.removeAll()
        
        for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.isEmpty {
                continue
            }
            
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                currentCategory = String(trimmedLine.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if let category = currentCategory, !category.isEmpty {
                    if allQuotes[category] == nil {
                        allQuotes[category] = []
                        categories.append(category)
                        print("📁 找到分类：\(category)（行号：\(lineNumber + 1)）")
                    }
                } else {
                    print("⚠️ 无效分类格式（行号：\(lineNumber + 1)）：\(trimmedLine)")
                }
            }
            else if let category = currentCategory, !trimmedLine.isEmpty {
                allQuotes[category]?.append(trimmedLine)
                print("💬 添加语录到\(category)：\(trimmedLine.prefix(20))...")
            } else {
                print("⚠️ 无法识别的内容（行号：\(lineNumber + 1)）：\(trimmedLine)")
            }
        }
    }
    
    func nextQuote() {
        guard hasData, !allQuotes.isEmpty else {
            currentQuote = "没有可用语录数据"
            return
        }
        
        let quotes: [String]
        
        if let category = currentCategory, let categoryQuotes = allQuotes[category], !categoryQuotes.isEmpty {
            quotes = categoryQuotes
        } else {
            let validCategories = allQuotes.filter { !$0.value.isEmpty }.keys
            guard let randomCategory = validCategories.randomElement() else {
                currentQuote = "所有分类都没有语录"
                hasData = false
                return
            }
            currentCategory = randomCategory
            quotes = allQuotes[randomCategory]!
        }
        
        var newIndex = currentIndex
        if quotes.count > 1 {
            repeat {
                newIndex = Int.random(in: 0..<quotes.count)
            } while newIndex == currentIndex
        }
        currentIndex = newIndex
        currentQuote = quotes[currentIndex]
        print("🔄 切换到新语录：\(currentQuote)")
    }
    
    func filterQuotes(by category: String) {
        guard hasData else { return }
        
        currentCategory = category
        guard let quotes = allQuotes[category], !quotes.isEmpty else {
            currentQuote = "该分类没有语录"
            return
        }
        
        currentIndex = Int.random(in: 0..<quotes.count)
        currentQuote = quotes[currentIndex]
        print("🔍 切换到分类：\(category)，语录：\(currentQuote)")
    }
    
    private func selectRandomQuote() {
        guard hasData, !allQuotes.isEmpty else { return }
        
        let validCategories = allQuotes.filter { !$0.value.isEmpty }.keys
        guard let randomCategory = validCategories.randomElement() else {
            currentQuote = "没有可用语录"
            hasData = false
            return
        }
        
        let quotes = allQuotes[randomCategory]!
        currentIndex = Int.random(in: 0..<quotes.count)
        currentQuote = quotes[currentIndex]
        currentCategory = randomCategory
    }
}

// 兼容性修饰符
struct SheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium])
        } else {
            content
        }
    }
}
