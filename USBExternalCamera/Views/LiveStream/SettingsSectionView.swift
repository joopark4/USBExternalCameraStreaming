import SwiftUI

/// 설정 섹션을 위한 재사용 가능한 컨테이너 뷰
struct SettingsSectionView<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 섹션 헤더
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)

            // 섹션 콘텐츠
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding(.vertical, 8)
    }
}