import SwiftUI
import PhotosUI

/// 홈 화면 위젯처럼 보이는 원 — 완성 스티커가 있으면 그 모습, 없으면 청록 추가 버튼.
/// 별도 View로 둔다 (MainView의 메서드로 두면 MainActor 격리가 번져 GeometryReader 클로저에서 못 쓴다).
struct WidgetCircle: View {
    let diameter: CGFloat
    let sticker: UIImage?
    let metrics: StickerMetrics?
    let placement: StickerPlacement?   // 사용자가 정한 배치 (없으면 자동)
    let background: Color
    let backgroundPattern: String?     // 패턴 에셋 이름 (있으면 색 대신 이미지)
    let foreground: Color
    let batteryPercent: Int
    let showBatteryPercent: Bool

    var body: some View {
        Circle()
            .fill(sticker == nil ? Color.brandCyan : Color.clear)
            .frame(width: diameter)
            .background {
                // 스티커가 있으면 위젯 배경(단색/패턴)을 원에 채운다
                if sticker != nil {
                    BackgroundFill(patternAsset: backgroundPattern, color: background)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                }
            }
            .overlay {
                if let sticker {
                    ZStack {
                        // 스티커 — 사용자 배치가 있으면 그대로, 없으면 자동 배치. 원 밖은 잘린다.
                        stickerLayer(sticker)

                        // 배터리 퍼센트 — 원 상단 근처 (스티커 위). Battery 토글이 꺼져 있으면 숨긴다.
                        if showBatteryPercent {
                            VStack(spacing: 0) {
                                Text("\(batteryPercent)%")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(foreground)
                                    .padding(.top, diameter * 0.117)   // 제작 화면과 동일 비율
                                Spacer()
                            }
                        }
                    }
                    .frame(width: diameter, height: diameter)
                } else {
                    Image("PlusIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                }
            }
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 4, y: 4)
    }

    @ViewBuilder
    private func stickerLayer(_ sticker: UIImage) -> some View {
        let image = Image(uiImage: sticker).resizable().scaledToFit()
        if let p = placement {
            let box = p.boxRatio * diameter
            image
                .frame(width: box, height: box)
                .rotationEffect(.degrees(p.rotation))
                .offset(x: p.offset.width * diameter, y: p.offset.height * diameter)
        } else {
            // 예전 스티커(배치 정보 없음) — 자동 배치
            let layout = StickerCircleLayout(diameter: diameter, metrics: metrics)
            image
                .frame(width: layout.size.width, height: layout.size.height)
                .offset(y: layout.offsetY)
        }
    }
}

struct MainView: View {
    @Environment(AppRouter.self) var router
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var pickedPhoto: PickedPhoto?
    @State private var isLoadingPhoto = false
    @State private var savedSticker: UIImage?   // 완성 후 청록 원에 표시할 스티커(위젯과 동일 결과)
    @State private var savedOriginal: UIImage?  // 다시 편집할 원본 사진 (없으면 편집 불가)
    @State private var stickerMetrics: StickerMetrics?   // 스티커 배치용 불투명 픽셀 분포(캐시)
    @State private var stickerPlacement: StickerPlacement?  // 사용자가 정한 배치
    @State private var widgetBackground: Color = .white   // 제작 화면에서 고른 위젯 배경색
    @State private var widgetPattern: String?             // 배경 패턴 에셋 (있으면 이미지)
    @State private var widgetForeground: Color = .black   // 그 위에 얹는 배터리 표시 색
    @AppStorage(SharedStore.showBatteryPercentKey, store: UserDefaults(suiteName: SharedStore.appGroupID))
    private var showBatteryPercent = false
    @State private var showAddWidgetGuide = false   // 첫 스티커 완성 직후 "위젯 추가" 안내 팝업
    @State private var showBatteryGuide = false      // 설치 후 처음 한 번, "배터리 표시 설정" 안내

    // 저장된 스티커와 배경을 함께 읽어 미리보기를 위젯과 같은 모습으로 맞춘다
    private func reloadWidgetPreview() {
        savedSticker = SharedStore.loadSticker()
        savedOriginal = SharedStore.loadOriginal()
        stickerMetrics = savedSticker.flatMap(StickerMetrics.analyze)
        stickerPlacement = StickerPlacement.saved()
        let colors = SharedStore.widgetColors()
        widgetBackground = colors.background
        widgetPattern = colors.pattern
        widgetForeground = colors.foreground
    }

    var body: some View {
        ZStack {
            Color.bgBase.ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // 딤 아래 요소
                Group {
                    // Stickie 로고 — 상단 중앙
                    Image("StickieLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 153, height: 24)
                        .position(x: w / 2, y: 30 + 25)

                    // 핑크 잠금 슬롯 — 좌상단
                    LockedSlot(size: 149, color: .brandPink)
                        .position(x: w * 0.242, y: h * 0.228 + 25)

                    // 라임 잠금 슬롯 — 좌하단
                    LockedSlot(size: 105, color: Color(hex: "A5DC0F"))
                        .position(x: w * 0.340, y: h * 0.843 + 25)
                }

                // 딤 레이어 — 잠금 슬롯 위, 청록 원 아래 (Figma 55:1376)
                // 1단계(위젯 추가 안내)에서만 원 아래에 깔아 원을 하이라이트한다.
                if showGuide {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // 원 — 딤 위. 완성 스티커를 탭하면 수정 뷰로, 없으면 사진 선택.
                let circle = WidgetCircle(
                    diameter: w * 0.72,
                    sticker: savedSticker,
                    metrics: stickerMetrics,
                    placement: stickerPlacement,
                    background: widgetBackground,
                    backgroundPattern: widgetPattern,
                    foreground: widgetForeground,
                    batteryPercent: BatteryMonitor.shared.percent,
                    showBatteryPercent: showBatteryPercent
                )
                Group {
                    if let savedOriginal {
                        // 완성 스티커를 탭하면 원본을 다시 불러 수정 뷰로 (이전 배치를 이어받는다)
                        Button {
                            pickedPhoto = PickedPhoto(image: savedOriginal, placement: stickerPlacement)
                        } label: { circle }
                    } else {
                        // 원본이 없으면(첫 제작이거나 원본 저장 이전 버전) 사진을 고르게 한다
                        PhotosPicker(selection: $selectedItem, matching: .images) { circle }
                    }
                }
                .buttonStyle(.plain)
                .position(x: w * 0.540, y: h * 0.524 + 25)

                // 가이드 텍스트·화살표 — 청록 원 위
                if showGuide {
                    MainGuideOverlay()
                        .transition(.opacity)
                }

                // 2단계(배터리 안내) 딤 — 청록 원 위에 덮어 원 하이라이트를 끈다.
                // (배터리 안내 텍스트·화살표는 이 딤 위 .overlay에서 그려져 그대로 보인다.)
                if showBatteryGuide {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        }
        // 설정 아이콘 — 우하단 (오른쪽 35, 아래 40). 배터리 가이드가 떠 있으면 아이콘 위에 나란히 쌓인다.
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if showBatteryGuide {
                    BatteryGuideOverlay()
                        .transition(.opacity)
                }
                Button {
                    showSettings = true
                } label: {
                    Image("SettingsIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 29, height: 29)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 35)
            .padding(.bottom, 40 - 25)
        }
        .overlay {
            if showAddWidgetGuide {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    Image("AddWidgetGuide")
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 24)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { showAddWidgetGuide = false }
                }
                .transition(.opacity)
            }
        }
        // 최초 진입 딤(showGuide)을 탭하면 → 다음 딤(배터리 설정 안내)으로 이어진다.
        // 설치 후 처음 한 번만 배터리 안내가 뜨고, 이후에는 딤만 닫힌다.
        .overlay {
            if showGuide {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showGuide = false
                            let hasSeenKey = "hasSeenBatteryGuide"
                            if !UserDefaults.standard.bool(forKey: hasSeenKey) {
                                UserDefaults.standard.set(true, forKey: hasSeenKey)
                                showBatteryGuide = true
                            }
                        }
                    }
            }
        }
        // 배터리 가이드가 떠 있는 동안은 화면 어디를 탭해도 가이드만 닫히고 메인뷰가 드러난다.
        .overlay {
            if showBatteryGuide {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.4)) { showBatteryGuide = false }
                    }
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView { showSettings = false }
        }
        .fullScreenCover(item: $pickedPhoto) { photo in
            MakeStickieView(originalImage: photo.image, initialPlacement: photo.placement) {
                let isFirstSticker = savedSticker == nil   // 완성 전에 스티커가 없었으면 첫 제작
                pickedPhoto = nil
                selectedItem = nil
                reloadWidgetPreview()   // 완성 결과(스티커·배경색·배치)를 원에 반영
                if isFirstSticker {
                    withAnimation(.easeInOut(duration: 0.25)) { showAddWidgetGuide = true }
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            isLoadingPhoto = true
            Task {
                // 원본 사진만 불러오고, 누끼·스트로크는 제작 화면에서 처리
                defer { Task { @MainActor in isLoadingPhoto = false } }
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                await MainActor.run {
                    pickedPhoto = PickedPhoto(image: uiImage)
                }
            }
        }
        .onAppear {
            reloadWidgetPreview()   // 이전에 만든 스티커가 있으면 저장된 배경색과 함께 표시
            showGuide = true        // 최초 진입 딤 — 탭하면 배터리 안내로 이어진다(아래 오버레이)
        }
    }
}


struct LockedSlot: View {
    let size: CGFloat
    let color: Color
    @State private var isRevealed = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background {
                    if isRevealed {
                        Circle().fill(Color(white: 0.45))
                    }
                }

            if isRevealed {
                Text("Coming\nSoon!")
                    .font(.system(size: size * 0.135, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.2))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            dismissTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { isRevealed = false }
            }
        }
    }
}

#Preview {
    MainView()
        .environment(AppRouter())
}

#Preview("Locked Slot") {
    HStack(spacing: 40) {
        LockedSlot(size: 149, color: .brandPink)
        LockedSlot(size: 105, color: Color(hex: "A5DC0F"))
    }
    .padding()
    .background(Color.bgBase)
}
