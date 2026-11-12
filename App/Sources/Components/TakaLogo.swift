import SwiftUI

/// The logo "৳akaDe" at rest: the split taka sign beside the outlined wordmark, placed
/// exactly as in docs/brand/logo-on-light.svg (TakaLockup). Reads as "TakaDe".
struct TakaLogo: View {
    var width: CGFloat
    var mark: Color = Color("launchMark")
    var word: Color = Color("launchWord")

    var body: some View {
        let side = TakaLockup.markSide * width
        let wordWidth = TakaLockup.wordWidth * width
        ZStack {
            TakaMark(split: 1)
                .foregroundStyle(mark)
                .frame(width: side, height: side)
                .offset(x: TakaLockup.markCenter.x * width, y: TakaLockup.markCenter.y * width)
            TakaWordmarkShape()
                .fill(word)
                .frame(width: wordWidth, height: wordWidth / TakaWordmarkShape.aspectRatio)
                .offset(x: TakaLockup.wordCenter.x * width, y: TakaLockup.wordCenter.y * width)
        }
        .frame(width: width, height: width * TakaLockup.heightRatio)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "TakaDe"))
        .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    TakaLogo(width: 280).padding().background(Color("launchBackground"))
}
