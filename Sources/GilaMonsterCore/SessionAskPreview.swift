import Foundation

#if DEBUG
extension SessionAccessService {
    /// Debug snapshots only (K786): a new service, never the shared one, holding one made-up ask, so the Allow prompt
    /// can be drawn without a session asking. It has no socket and answers nothing: resolving does nothing anyone waits on.
    public static func preview(caller: String, action: SessionAction, server: String, wait: TimeInterval) -> SessionAccessService {
        let service = SessionAccessService()
        let now = Date()
        service.waiting = [SessionApproval(id: UUID(), caller: caller, action: action, server: server, recipe: nil, asked: now, deadline: now.addingTimeInterval(wait))]
        return service
    }
}
#endif
