import Foundation

#if DEBUG
extension SessionAccessService {
    /// Debug snapshots only (K786): a new service, never the shared one, holding one made-up ask, so the Allow prompt
    /// can be drawn without a session asking. It has no socket and answers nothing: resolving does nothing anyone waits on.
    public static func preview(caller: String, action: SessionAction, server: String, wait: TimeInterval, extensions: Int = 0) -> SessionAccessService {
        let service = SessionAccessService()
        let now = Date()
        service.waiting = [SessionApproval(id: UUID(), caller: caller, action: action, server: server, recipe: nil, asked: now, deadline: now.addingTimeInterval(wait))]
        service.waiting[0].extensions = extensions
        return service
    }

    /// What "Need More Time" does to the first row of a preview, which has nobody waiting for `extend` to answer.
    public func previewExtend() {
        guard !waiting.isEmpty, waiting[0].extensions < Self.maxExtensions else { return }
        waiting[0].extensions += 1
        waiting[0].deadline = waiting[0].deadline.addingTimeInterval(approvalExtension)
    }
}
#endif
