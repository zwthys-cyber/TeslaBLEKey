import SwiftUI

struct VehicleIdentityView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var vin = ""
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var showingScanner = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 52, height: 52)
                    .background(AppTheme.raised, in: Circle())

                Text("解锁完整控制")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.6)
                    .padding(.top, 22)
                Text("Tesla 的空调、车窗和车载系统使用 VIN 建立端到端加密会话。仅需设置一次，数据只保存在本机。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("车辆识别码").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    TextField("17 位 VIN", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(validationMessage == nil ? AppTheme.hairline : Color.red.opacity(0.7), lineWidth: 0.7))
                        .focused($isFocused)
                        .onChange(of: vin) { _, value in
                            vin = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(17))
                            validationMessage = nil
                        }
                    Text(validationMessage ?? "在车机中打开「控制 > 软件」即可查看")
                        .font(.caption)
                        .foregroundStyle(validationMessage == nil ? AppTheme.muted : Color.red)
                }
                .padding(.top, 28)

                Button {
                    showingScanner = true
                } label: {
                    Label("扫描车机上的 VIN", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.7))
                .padding(.top, 14)

                Spacer()

                Button {
                    isSaving = true
                    Task {
                        validationMessage = await vehicle.saveVehicleVIN(vin)
                        isSaving = false
                        if validationMessage == nil { dismiss() }
                    }
                } label: {
                    Group {
                        if isSaving { ProgressView().tint(.black) }
                        else { Text("验证并启用").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .disabled(vin.count != 17 || isSaving)
                .opacity(vin.count == 17 ? 1 : 0.45)
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("稍后") { dismiss() }.foregroundStyle(AppTheme.muted)
                }
            }
            .onAppear { isFocused = true }
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    VINScannerView { value in
                        vin = value
                        showingScanner = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("扫描 VIN")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { showingScanner = false } } }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
