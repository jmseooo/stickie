import WidgetKit
import SwiftUI

// 사용자가 수정 뷰에서 핀치·드래그·회전으로 정한 스티커 배치 (한 변 대비 비율)
struct WidgetPlacement {
    let boxRatio: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotation: Double
}

// 위젯 한 칸에 담기는 데이터 — 다운샘플링된 작은 스티커 PNG (Data는 Sendable) + 배경/전경색
struct StickerEntry: TimelineEntry {
    let date: Date
    let imageData: Data?
    let background: Color
    let backgroundPattern: String?   // 패턴 에셋 이름 (있으면 색 대신 이미지 배경)
    let foreground: Color    // 배경 위 배터리 표시 색 (어두운 배경에선 흰색)
    let batteryPercent: Int
    let showBatteryPercent: Bool   // 설정 화면의 Battery 토글값
    let placement: WidgetPlacement?   // nil이면 예전 방식(자동 여백)으로 그린다

    static func current(imageData: Data?) -> StickerEntry {
        let colors = SharedStore.widgetColors()
        // 익스텐션에서 UIDevice 값이 갱신되지 않는 경우가 있어, 앱이 남긴 값으로 대비한다
        let percent = Battery.currentPercent()
            ?? SharedStore.lastKnownBatteryPercent()
            ?? Battery.fallbackPercent
        let placement = SharedStore.stickerTransform().map {
            WidgetPlacement(boxRatio: $0.boxRatio, offsetX: $0.offsetX, offsetY: $0.offsetY, rotation: $0.rotation)
        }
        return StickerEntry(
            date: Date(),
            imageData: imageData,
            background: colors.background,
            backgroundPattern: colors.pattern,
            foreground: colors.foreground,
            batteryPercent: percent,
            showBatteryPercent: SharedStore.showBatteryPercent(),
            placement: placement
        )
    }
}

// 공유 저장소에서 스티커를 (메모리 안전하게) 읽어 타임라인을 구성
struct StickerProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickerEntry {
        // 위젯 갤러리(추가 화면) 미리보기는 이 placeholder를 그린다.
        // imageData를 nil로 두면 잠금화면 원형이 pawprint 아이콘으로 떨어지므로,
        // 실제 저장된 스티커를 읽어 추가 전에도 실루엣 미리보기가 보이게 한다.
        .current(imageData: SharedStore.widgetImageData())
    }

    func getSnapshot(in context: Context, completion: @escaping (StickerEntry) -> Void) {
        completion(.current(imageData: SharedStore.widgetImageData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StickerEntry>) -> Void) {
        // 스티커·배경색은 앱이 저장할 때 갱신을 요청하지만, 배터리는 스스로 바뀌므로
        // 주기적으로 다시 읽는다. iOS가 새로고침 예산을 관리하므로 실제 주기는 더 길 수 있다.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [.current(imageData: SharedStore.widgetImageData())], policy: .after(next)))
    }
}

struct StickieWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StickerEntry

    // containerBackground는 반드시 위젯 뷰 최상단에 둔다.
    // switch 분기 안쪽에 두면 WidgetKit이 못 찾아 실기기에서 회색 플레이스홀더로 떨어진다.
    var body: some View {
        Group {
            if family == .accessoryCircular {
                lockScreenCircular
            } else {
                homeScreen
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular {
                AccessoryWidgetBackground()
            } else if let pattern = entry.backgroundPattern {
                // 앱 Background 팔레트에서 고른 패턴 이미지
                Image(pattern).resizable().scaledToFill()
            } else {
                // 단색 배경
                entry.background
            }
        }
        // 위젯 갤러리(추가 화면) 미리보기가 회색 스켈레톤(redacted)으로 뜨지 않고
        // 실제 로고·스티커를 그리도록 redaction을 끈다.
        .unredacted()
    }

    // 잠금화면 원형 위젯. iOS는 잠금화면 위젯을 vibrant(단색 재질)로만 렌더한다.
    // 사진의 명암이 비쳐 지저분해지지 않도록, 알파(모양)만 남겨 단색으로 꽉 채운 실루엣으로 그린다.
    private var lockScreenCircular: some View {
        ZStack {
            if let data = entry.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .renderingMode(.template)   // RGB 무시, 불투명 영역을 단색으로 채움
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(3)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 22))
            }
        }
    }

    // 홈 화면 위젯 (배터리 + 스티커 + 배경색/패턴)
    private var homeScreen: some View {
        GeometryReader { geo in
            ZStack {
                // 배터리 퍼센트 — 위젯 상단. 스티커가 있을 때만(빈 상태에는 로고만) 표시.
                if entry.showBatteryPercent, entry.imageData != nil {
                    VStack {
                        Text("\(entry.batteryPercent)%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(entry.foreground)
                            // 위젯 크기에 비례한 상단 여백 (스티커 안전선 0.24h 위)
                            .padding(.top, geo.size.height * 0.08)
                        Spacer()
                    }
                }

                if let data = entry.imageData, let image = UIImage(data: data) {
                    if let p = entry.placement {
                        // 사용자가 정한 배치 — 한 변 대비 비율로 크기·위치를 재현한다.
                        // 위젯 밖은 시스템이 자동 클리핑한다.
                        let base = geo.size.width
                        let box = p.boxRatio * base
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: box, height: box)
                            .rotationEffect(.degrees(p.rotation))
                            .offset(x: p.offsetX * base, y: p.offsetY * base)
                    } else {
                        // 예전 스티커(배치 정보 없음) — 상단 배터리를 피하는 자동 여백
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(.top, geo.size.height * 0.24)
                            .padding([.horizontal, .bottom], 6)
                    }
                } else {
                    // 아직 스티커를 만들지 않은 경우 — 로고만 중앙에 크게
                    Image("StickieBigLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 0.9)
                }
            }
            // GeometryReader는 자식을 좌상단에 두므로, 위젯 전체를 채워 중앙 정렬되게 함
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct StickieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: StickerProvider()) { entry in
            StickieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Stickie")
        .description("Show your pet stickers on the Home Screen and Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()   // 투명 배경 위에 스티커가 꽉 차게
    }
}

#Preview(as: .accessoryCircular) {
    StickieWidget()
} timeline: {
    StickerEntry(date: Date(), imageData: nil, background: .white, backgroundPattern: nil, foreground: .black, batteryPercent: 100, showBatteryPercent: true, placement: nil)
}
