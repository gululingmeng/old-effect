import Foundation

enum QuestionRepository {
    /// Replace these 50 placeholder strings with your final copy.
    /// Keeping the data source separate makes later maintenance easy.
    static let questions: [String] = [
        "你现在过上想要的生活了吗？", "你还记得最初想成为什么吗？", "你还在坚持当年的梦吗？", "你活成自己喜欢的人了吗？", "你现在的选择，你满意吗？", "你还相信自己能改变人生吗？", "你是不是也变成了普通的大人？", "你还敢为自己赌一次吗？", "你现在真的快乐吗？", "你还喜欢现在的自己吗？", "你有没有活成别人期待的样子？", "你还记得自己为什么出发吗？", "你现在的努力，值得吗？", "你还有重新开始的勇气吗？", "你还会为热爱熬夜吗？", "你现在拥有的，是你想要的吗？", "你有没有好好爱过一个人？", "你有没有好好陪过家人？", "你学会和自己和解了吗？", "你会因为遗憾难过吗？", "你还会被一点小事感动吗？", "你现在害怕老去吗？", "你会羡慕现在的自己吗？","你现在觉得幸福吗？", "你现在觉得开心吗？", "有什么具体的瞬间，让你突然觉得“真好啊”？是一顿饭，一句话，还是一个普通的傍晚？", "还会在半夜偷偷EMO吗？", "上学开心吗？让你有成就感吗？", "你现在是一个人，还是有人陪在你身边了？", "爸妈身体还好吗？你常回去看他们吗？", "有学会一项很棒的新技能吗？是终于能下厨做一桌子菜，还是学会了弹一首喜欢的曲子？", "身体健康吗？有没有坚持运动？", "你还会容易被小事打动吗？", "你现在成为小时候想成为的那种大人了吗？", "和最好的朋友还常常联系吗？", "你还在坚持记录生活吗？是用什么方式？", "你害怕的东西变少了吗？", "如果可以对未来的自己说一句话，你会说什么？"]

    static func randomQuestion(excluding excluded: String? = nil) -> String {
        guard !questions.isEmpty else {
            return "暂无可显示的问题"
        }

        if questions.count == 1 {
            return questions[0]
        }

        let filtered = questions.filter { $0 != excluded }
        return filtered.randomElement() ?? questions.randomElement() ?? "暂无可显示的问题"
    }
}
