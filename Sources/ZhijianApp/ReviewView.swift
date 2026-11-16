import SwiftUI
import DictionaryCore

struct ReviewView:View {
    @EnvironmentObject private var model:AppModel
    @State private var revealed=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    Label("温故知新",systemImage:"leaf").font(.system(size:12,weight:.medium))
                    Spacer()
                    Text("本次已温习 \(model.reviewedThisSession) 个").font(.system(size:11)).monospacedDigit()
                }.foregroundStyle(Palette.secondary).padding(.bottom,45)
                if let entry=model.selectedEntry {
                    Text("试着，用自己的话说说。").font(.custom("Songti SC",size:25)).padding(.bottom,35)
                    Text(entry.title).font(Palette.title).padding(.bottom,10)
                    Text(entry.content.english).font(.system(size:14)).foregroundStyle(Palette.secondary).padding(.bottom,30)
                    if !entry.content.sourceTitle.isEmpty { Label(entry.content.sourceTitle,systemImage:"text.book.closed").font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.bottom,30) }
                    Divider().overlay(Palette.rule).padding(.bottom,30)
                    if revealed {
                        Text(entry.summary).font(.custom("Songti SC",size:24)).lineSpacing(8).foregroundStyle(Palette.accent).padding(.bottom,24)
                        Text(entry.content.analogy).readingText().padding(.bottom,25)
                        if !entry.content.personalNote.isEmpty {
                            VStack(alignment:.leading,spacing:10) { SectionTitle(title:"你上次的理解",symbol:"pencil.line"); Text(entry.content.personalNote).readingText() }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Palette.note,in:RoundedRectangle(cornerRadius:9)).padding(.bottom,28)
                        }
                        Text("现在，你理解到哪一步？").font(.system(size:12)).foregroundStyle(Palette.secondary).padding(.bottom,14)
                        HStack(spacing:10) {
                            rating("还没懂",subtitle:"10 分钟后",value:0,entry:entry)
                            rating("有点模糊",subtitle:"2 天后",value:1,entry:entry)
                            rating("能讲明白",subtitle:"\(min(60,7*(entry.reviewCount+1))) 天后",value:2,entry:entry)
                        }.disabled(model.isSaving)
                    } else {
                        VStack(alignment:.leading,spacing:18) {
                            Text("先别急着看答案。\n想一个比喻，或者回想它在文章里做了什么。").font(.system(size:15)).lineSpacing(8).foregroundStyle(Palette.secondary)
                            Button { revealed=true } label:{ Label("看看解释",systemImage:"eye").frame(minWidth:115) }.buttonStyle(MossButtonStyle()).padding(.top,12)
                        }.padding(.vertical,20)
                    }
                } else if !model.isLoading {
                    Image(systemName:"leaf").font(.system(size:45,weight:.ultraLight)).foregroundStyle(Palette.accent).padding(.bottom,25)
                    Text(model.reviewedThisSession > 0 ? "今天，又熟悉了一点。":"现在没有待温习的概念。").font(Palette.heading).padding(.bottom,15)
                    Text("不必一次记住所有。下次到期，再回来看看。").font(.system(size:14)).foregroundStyle(Palette.secondary).padding(.bottom,30)
                    Button("回到词典") { model.section = .all }.buttonStyle(MossButtonStyle())
                }
                Spacer(minLength:50)
            }.frame(maxWidth:660,alignment:.leading).padding(42).frame(maxWidth:.infinity,alignment:.center)
        }.background(Palette.paper).onChange(of:model.selectedEntry?.id) { _,_ in revealed=false }
    }
    private func rating(_ title:String,subtitle:String,value:Int,entry:Entry) -> some View {
        Button { Task { await model.rate(entry,rating:value); revealed=false } } label:{
            VStack(spacing:7) { Text(title).font(.system(size:13,weight:.medium)); Text(subtitle).font(.system(size:10)).foregroundStyle(Palette.secondary) }
                .frame(maxWidth:.infinity).padding(.vertical,17).background(value==2 ? Palette.selection:Palette.note,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).pointingHandCursor().foregroundStyle(Palette.accent)
    }
}
