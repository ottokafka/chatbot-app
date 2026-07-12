import SwiftUI

// MARK: - System Prompt Modal View
struct SystemPromptModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var newTitle = ""
    @State private var newPromptText = ""
    @State private var isGenerating = false
    @State private var editingPrompt: SystemPrompt? = nil
    @State private var hoveredPromptId: String? = nil
    @State private var iOSActiveTab = 0
    
    var body: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            Picker("", selection: $iOSActiveTab) {
                Text(L10n.tabSelect(lang)).tag(0)
                Text(L10n.tabCreateEdit(lang)).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if iOSActiveTab == 0 {
                // Select System Prompt List
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.selectSystemPrompt(lang))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.systemPrompts) { prompt in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .center) {
                                        Text(prompt.title)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        // Edit button
                                        Button(action: {
                                            editingPrompt = prompt
                                            newTitle = prompt.title
                                            newPromptText = prompt.promptText
                                            iOSActiveTab = 1
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // Delete button
                                        Button(action: {
                                            viewModel.deleteSystemPrompt(prompt)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text(prompt.promptText)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(prompt.isActive ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(prompt.isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: prompt.isActive ? 2 : 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectSystemPrompt(prompt)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            } else {
                // Create/Edit Prompt Form
                VStack(alignment: .leading, spacing: 16) {
                    
                    HStack(spacing: 8) {
                        // Title Field
                        TextField(L10n.promptTitlePlaceholder(lang), text: $newTitle)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .font(.body)
                        
                        // AI Prompt Generation Button
                        Button(action: {
                            generatePromptWithAI()
                        }) {
                            HStack(spacing: 6) {
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("AI")
                                }
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.purple.opacity(0.3) : Color.purple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                    
                    // Prompt Content Area
                    TextEditor(text: $newPromptText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    HStack(spacing: 12) {
                        // Cancel button
                        Button(action: {
                            if editingPrompt != nil {
                                editingPrompt = nil
                                newTitle = ""
                                newPromptText = ""
                                iOSActiveTab = 0
                            } else {
                                dismiss()
                            }
                        }) {
                            Text(L10n.cancel(lang))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        // Save/Update Button
                        Button(action: {
                            savePrompt()
                            iOSActiveTab = 0
                        }) {
                            Text(editingPrompt == nil ? L10n.savePrompt(lang) : L10n.updatePrompt(lang))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(newTitle.isEmpty || newPromptText.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.isEmpty || newPromptText.isEmpty)
                    }
                }
                .padding(20)
                .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            }
        }
        .preferredColorScheme(.dark)
        #else
        HStack(spacing: 0) {
            // LEFT COLUMN: Select System Prompt (60% width)
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.selectSystemPrompt(lang))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.systemPrompts) { prompt in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .center) {
                                    Text(prompt.title)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    // Edit button
                                    Button(action: {
                                        editingPrompt = prompt
                                        newTitle = prompt.title
                                        newPromptText = prompt.promptText
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.editSystemPromptHelp(lang))
                                    
                                    // Delete button
                                    Button(action: {
                                        viewModel.deleteSystemPrompt(prompt)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.deleteSystemPromptHelp(lang))
                                }
                                
                                Text(prompt.promptText)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(prompt.isActive ? Color.blue.opacity(0.15) : (hoveredPromptId == prompt.id ? Color.gray.opacity(0.18) : Color.gray.opacity(0.1)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(prompt.isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: prompt.isActive ? 2 : 1)
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredPromptId = prompt.id
                                } else if hoveredPromptId == prompt.id {
                                    hoveredPromptId = nil
                                }
                            }
                            .onTapGesture {
                                viewModel.selectSystemPrompt(prompt)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // RIGHT COLUMN: Create/Edit Prompt (40% width)
            VStack(alignment: .leading, spacing: 16) {
                
                // Title Field
                TextField(L10n.promptTitlePlaceholder(lang), text: $newTitle)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .font(.body)
                
                // AI Prompt Generation Button
                Button(action: {
                    generatePromptWithAI()
                }) {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text(L10n.generating(lang))
                        } else {
                            Text(L10n.generatePromptWithAI(lang))
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.purple.opacity(0.3) : Color.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                
                // Prompt Content Area
                TextEditor(text: $newPromptText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                // Save/Update Button
                Button(action: {
                    savePrompt()
                }) {
                    Text(editingPrompt == nil ? L10n.savePrompt(lang) : L10n.updatePrompt(lang))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(newTitle.isEmpty || newPromptText.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.isEmpty || newPromptText.isEmpty)
                
                // Cancel button
                Button(action: {
                    if editingPrompt != nil {
                        editingPrompt = nil
                        newTitle = ""
                        newPromptText = ""
                    } else {
                        dismiss()
                    }
                }) {
                    Text(L10n.cancel(lang))
                        .foregroundColor(.gray)
                        .underline()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(minWidth: 320, maxWidth: 320, maxHeight: .infinity)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
        }
        .frame(width: 780, height: 480)
        .preferredColorScheme(.dark)
        #endif
    }
    
    private func generatePromptWithAI() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        
        isGenerating = true
        Task {
            if let result = await viewModel.generatePromptText(for: title) {
                newPromptText = result
            }
            isGenerating = false
        }
    }
    
    private func savePrompt() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptText = newPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !title.isEmpty && !promptText.isEmpty else { return }
        
        if let existing = editingPrompt {
            viewModel.updateSystemPrompt(existing, title: title, promptText: promptText)
        } else {
            viewModel.createSystemPrompt(title: title, promptText: promptText)
        }
        
        newTitle = ""
        newPromptText = ""
        editingPrompt = nil
    }
}

