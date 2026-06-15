import SwiftUI

struct EQView: View {
    @Binding var lowGain: Float
    @Binding var midGain: Float
    @Binding var highGain: Float
    var onChange: (() -> Void)?

    // gain range in dB
    let minGain: Float = -12
    let maxGain: Float = 12

    var body: some View {
        VStack(spacing: 10) {
            // 标题栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                    Text("均衡器")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                Text(String(format: "L %+.0f  M %+.0f  H %+.0f dB", lowGain, midGain, highGain))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // 主体曲线区域
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let inset: CGFloat = 16
                    let drawW = w - inset * 2
                    let drawH = h - inset * 2

                    // 中心基线
                    Path { path in
                        path.move(to: CGPoint(x: inset, y: h/2))
                        path.addLine(to: CGPoint(x: w - inset, y: h/2))
                    }
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    // 网格线
                    Path { path in
                        // 水平网格
                        for i in 1..<4 {
                            let y = inset + drawH * CGFloat(i) / 4.0
                            path.move(to: CGPoint(x: inset, y: y))
                            path.addLine(to: CGPoint(x: w - inset, y: y))
                        }
                        // 垂直网格
                        for i in 1..<4 {
                            let x = inset + drawW * CGFloat(i) / 4.0
                            path.move(to: CGPoint(x: x, y: inset))
                            path.addLine(to: CGPoint(x: x, y: h - inset))
                        }
                    }
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)

                    // 三个控制点的位置
                    let x1 = inset + drawW * 0.18
                    let x2 = inset + drawW * 0.5
                    let x3 = inset + drawW * 0.82

                    let y: (Float) -> CGFloat = { g in
                        let t = CGFloat((g - self.minGain) / (self.maxGain - self.minGain))
                        return h - inset - t * drawH
                    }

                    let p1 = CGPoint(x: x1, y: y(lowGain))
                    let p2 = CGPoint(x: x2, y: y(midGain))
                    let p3 = CGPoint(x: x3, y: y(highGain))

                    // 填充区域
                    Path { path in
                        path.move(to: CGPoint(x: inset, y: h/2))
                        path.addLine(to: p1)
                        path.addQuadCurve(to: p2, control: p1)
                        path.addQuadCurve(to: p3, control: p3)
                        path.addLine(to: CGPoint(x: w - inset, y: h/2))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.pink.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 曲线
                    Path { path in
                        path.move(to: CGPoint(x: inset, y: h/2))
                        path.addQuadCurve(to: p2, control: p1)
                        path.addQuadCurve(to: CGPoint(x: w - inset, y: h/2), control: p3)
                    }
                    .stroke(
                        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                    // 三个可拖动的控制点
                    DraggableEQPoint(
                        position: p1,
                        gain: $lowGain,
                        minGain: minGain,
                        maxGain: maxGain,
                        color: .blue,
                        label: "LOW",
                        frequency: "80 Hz",
                        onChange: onChange
                    )
                    DraggableEQPoint(
                        position: p2,
                        gain: $midGain,
                        minGain: minGain,
                        maxGain: maxGain,
                        color: .purple,
                        label: "MID",
                        frequency: "1 kHz",
                        onChange: onChange
                    )
                    DraggableEQPoint(
                        position: p3,
                        gain: $highGain,
                        minGain: minGain,
                        maxGain: maxGain,
                        color: .pink,
                        label: "HIGH",
                        frequency: "8 kHz",
                        onChange: onChange
                    )
                }
            }
            .frame(height: 110)
            .padding(.horizontal, 12)

            // 底部说明
            HStack(spacing: 16) {
                Label("20–250 Hz", systemImage: "speaker.wave.1.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
                Label("250–4k Hz", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.purple.opacity(0.8))
                Label("4k–20k Hz", systemImage: "speaker.wave.3.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.pink.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3), .pink.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct DraggableEQPoint: View {
    let position: CGPoint
    @Binding var gain: Float
    let minGain: Float
    let maxGain: Float
    let color: Color
    let label: String
    let frequency: String
    var onChange: (() -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        // 使用 overlay + position 来精确定位
        ZStack {
            // 圆形控制点
            ZStack {
                // 外层光晕
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: isDragging ? 36 : 28, height: isDragging ? 36 : 28)
                    .blur(radius: 4)

                // 主圆点
                Circle()
                    .fill(
                        LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 22, height: 22)

                // 中心点
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            .shadow(color: color.opacity(0.5), radius: isDragging ? 8 : 4, x: 0, y: 2)
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        }
        .position(x: position.x, y: position.y)
        .offset(y: dragOffset.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                    // 计算新的 dB 值 - 大幅降低弹性
                    let containerHeight: CGFloat = 110
                    let inset: CGFloat = 16
                    let drawH = containerHeight - inset * 2
                    let currentY = position.y + value.translation.height
                    let centerY = containerHeight / 2

                    // 大幅增加死区：圆点周围 20 像素内不响应
                    let deadZone: CGFloat = 20
                    let rawOffset = value.translation.height
                    if abs(rawOffset) <= deadZone {
                        // 死区内，保持当前值不变
                        return
                    }

                    // 死区外的拖动距离需要除以 3 降低弹性
                    let effectiveOffset = (rawOffset - (rawOffset > 0 ? deadZone : -deadZone)) / 3
                    let effectiveDrawH = drawH - deadZone
                    let normalized = (centerY - position.y - effectiveOffset + effectiveDrawH) / (effectiveDrawH * 2)
                    let t = max(0, min(1, normalized))
                    let newGain = minGain + Float(t) * (maxGain - minGain)
                    // 四舍五入到 0.5 dB
                    gain = (newGain * 2).rounded() / 2
                    onChange?()
                }
                .onEnded { _ in
                    isDragging = false
                    dragOffset = .zero
                }
        )
    }
}

struct EQView_Previews: PreviewProvider {
    static var previews: some View {
        EQView(lowGain: .constant(0), midGain: .constant(0), highGain: .constant(0))
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
