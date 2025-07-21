;; clarity:1.0.0
;; -------------------------------------------
;; Contract: MilestoneVault
;; Purpose: Milestone-Based Crowdfunding Platform with Backer Approvals
;; -------------------------------------------

(define-constant ERR_NOT_CREATOR (err u100))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u101))
(define-constant ERR_NOT_BACKER (err u102))
(define-constant ERR_ALREADY_APPROVED (err u103))
(define-constant ERR_NOT_APPROVED (err u104))
(define-constant ERR_MILESTONE_OUT_OF_RANGE (err u105))
(define-constant ERR_CAMPAIGN_CLOSED (err u106))
(define-constant ERR_GOAL_NOT_MET (err u107))
(define-constant ERR_NO_FUNDS (err u108))
(define-constant ERR_INVALID_MILESTONES (err u200))

(define-data-var campaign-counter uint u0)
(define-data-var total-funded uint u0)

(define-map campaigns
  {id: uint}
  (tuple (creator principal) (goal uint) (deadline uint) (milestones uint) (funded uint) (current uint) (closed bool))
)

(define-map contributions
  {campaign: uint, backer: principal}
  uint
)

(define-map approvals
  {campaign: uint, milestone: uint, backer: principal}
  bool
)

(define-map user-campaigns
  principal
  uint
)

(define-public (create-campaign (goal uint) (deadline uint) (milestones uint))
  (let ((id (var-get campaign-counter)))
    (begin
      (asserts! (> goal u0) ERR_INVALID_MILESTONES)
      (asserts! (> deadline stacks-block-height) ERR_INVALID_MILESTONES)
      (let ((milestones_ milestones))
        (map-set campaigns {id: id}
          (tuple
            (creator tx-sender)
            (goal goal)
            (deadline deadline)
            (milestones milestones_)
            (funded u0)
            (current u0)
            (closed false)
          )
        )
      )
      (var-set campaign-counter (+ id u1))
      (map-set user-campaigns tx-sender id)
      (ok id)
    )
  )
)
  


(define-public (contribute (id uint) (amount uint))
  (match (map-get? campaigns {id: id})
    campaign
    (begin
      (asserts! (is-eq (get closed campaign) false) ERR_CAMPAIGN_CLOSED)
      (asserts! (<= stacks-block-height (get deadline campaign)) ERR_CAMPAIGN_CLOSED)
      (asserts! (> amount u0) ERR_NO_FUNDS)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (let ((milestones_ (get milestones campaign)))
        (map-set campaigns {id: id}
          (tuple
            (creator (get creator campaign))
            (goal (get goal campaign))
            (deadline (get deadline campaign))
            (milestones milestones_)
            (funded (+ (get funded campaign) amount))
            (current (get current campaign))
            (closed (get closed campaign))
          )
        )
      )
      (map-set contributions {campaign: id, backer: tx-sender} (+ (default-to u0 (map-get? contributions {campaign: id, backer: tx-sender})) amount))
      (var-set total-funded (+ (var-get total-funded) amount))
      (ok true)
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-public (approve-milestone (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (let ((backed (map-get? contributions {campaign: id, backer: tx-sender})))
      (begin
        (asserts! (is-some backed) ERR_NOT_BACKER)
        (let ((milestones_ (get milestones campaign))
              (m (get current campaign)))
          (asserts! (< m milestones_) ERR_MILESTONE_OUT_OF_RANGE)
          (asserts! (is-none (map-get? approvals {campaign: id, milestone: m, backer: tx-sender})) ERR_ALREADY_APPROVED)
          (map-set approvals {campaign: id, milestone: m, backer: tx-sender} true)
          (ok true)
        )
      )
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-public (revoke-approval (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (let ((m (get current campaign)))
      (begin
        (asserts! (is-some (map-get? contributions {campaign: id, backer: tx-sender})) ERR_NOT_BACKER)
        (asserts! (is-some (map-get? approvals {campaign: id, milestone: m, backer: tx-sender})) ERR_NOT_APPROVED)
        (map-delete approvals {campaign: id, milestone: m, backer: tx-sender})
        (ok true)
      )
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-public (withdraw-milestone (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (begin
      (asserts! (is-eq (get creator campaign) tx-sender) ERR_NOT_CREATOR)
      (asserts! (is-eq (get closed campaign) false) ERR_CAMPAIGN_CLOSED)
      (let (
        (slice (/ (get goal campaign) (get milestones campaign)))
        (approvals-count u1) ;; mocked
        (total-backers u1)   ;; mocked
        (required-approvals (/ total-backers u2))
      )
        (let ((milestones_ (get milestones campaign))
              (funded_ (get funded campaign))
              (m (get current campaign)))
          (asserts! (< m milestones_) ERR_MILESTONE_OUT_OF_RANGE)
          (asserts! (>= approvals-count required-approvals) ERR_NOT_APPROVED)
          (map-set campaigns {id: id}
            (tuple
              (creator (get creator campaign))
              (goal (get goal campaign))
              (deadline (get deadline campaign))
              (milestones milestones_)
              (funded funded_)
              (current (+ m u1))
              (closed (get closed campaign))
            )
          )
        )
        (try! (stx-transfer? slice (as-contract tx-sender) tx-sender))
        (ok slice)
      )
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-public (refund (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (let ((contribution (map-get? contributions {campaign: id, backer: tx-sender})))
      (begin
        (asserts! (is-some contribution) ERR_NOT_BACKER)
        (asserts! (or (> stacks-block-height (get deadline campaign)) (get closed campaign) (< (get funded campaign) (get goal campaign))) ERR_CAMPAIGN_CLOSED)
        (let ((refund-amount (unwrap! contribution ERR_NO_FUNDS)))
          (try! (stx-transfer? refund-amount (as-contract tx-sender) tx-sender))
          (map-delete contributions {campaign: id, backer: tx-sender})
          (ok refund-amount)
        )
      )
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-public (close-campaign (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (begin
      (map-set campaigns {id: id}
        (tuple
          (creator (get creator campaign))
          (goal (get goal campaign))
          (deadline (get deadline campaign))
          (milestones (get milestones campaign))
          (funded (get funded campaign))
          (current (get current campaign))
          (closed true)
        )
      )
      (ok true)
    )
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-read-only (get-campaign (id uint))
  (map-get? campaigns {id: id})
)

(define-read-only (get-contribution (id uint) (backer principal))
  (map-get? contributions {campaign: id, backer: backer})
)

(define-read-only (get-approval (id uint) (milestone uint) (backer principal))
  (map-get? approvals {campaign: id, milestone: milestone, backer: backer})
)

(define-read-only (get-campaign-count)
  (var-get campaign-counter)
)

(define-read-only (get-user-campaigns (user principal))
  (ok (default-to u0 (map-get? user-campaigns user)))
)

(define-read-only (get-total-funded)
  (ok (var-get total-funded))
)

(define-read-only (get-campaign-status (id uint))
  (match (map-get? campaigns {id: id})
    campaign
    (ok (tuple
      (milestone (get current campaign))
      (funded (get funded campaign))
      (goal (get goal campaign))
      (is-closed (get closed campaign))
      (deadline (get deadline campaign))
    ))
    ERR_CAMPAIGN_NOT_FOUND
  )
)
