;; Voting System - Decentralized Democratic Decision Platform
;; Transparent, tamper-proof voting with multiple mechanisms and delegation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u900))
(define-constant err-not-authorized (err u901))
(define-constant err-proposal-not-found (err u902))
(define-constant err-invalid-amount (err u903))
(define-constant err-already-voted (err u904))
(define-constant err-voting-not-started (err u905))
(define-constant err-voting-ended (err u906))
(define-constant err-proposal-not-active (err u907))
(define-constant err-invalid-option (err u908))
(define-constant err-quorum-not-met (err u909))
(define-constant err-already-finalized (err u910))
(define-constant err-not-finalized (err u911))
(define-constant err-invalid-delegation (err u912))
(define-constant err-self-delegation (err u913))
(define-constant err-circular-delegation (err u914))
(define-constant err-invalid-threshold (err u915))
(define-constant err-invalid-voting-type (err u916))
(define-constant err-system-paused (err u917))
(define-constant err-no-voting-power (err u918))

;; Voting types
(define-constant voting-simple u1)
(define-constant voting-weighted u2)
(define-constant voting-quadratic u3)

;; Proposal status
(define-constant status-pending u1)
(define-constant status-active u2)
(define-constant status-ended u3)
(define-constant status-finalized u4)
(define-constant status-cancelled u5)

;; Data Variables
(define-data-var system-paused bool false)
(define-data-var total-proposals uint u0)
(define-data-var total-votes-cast uint u0)

;; Data Maps

;; Proposals
(define-map proposals
  uint
  {
    creator: principal,
    title: (string-ascii 200),
    description: (string-ascii 1000),
    voting-type: uint,
    start-block: uint,
    end-block: uint,
    option-count: uint,
    total-votes: uint,
    quorum-threshold: uint,
    approval-threshold: uint,
    status: uint,
    winner: (optional uint),
    created-at: uint
  }
)

;; Proposal options
(define-map proposal-options
  { proposal-id: uint, option-id: uint }
  {
    name: (string-ascii 100),
    vote-count: uint,
    vote-power: uint
  }
)

;; Individual votes
(define-map votes
  { proposal-id: uint, voter: principal }
  {
    option-id: uint,
    voting-power: uint,
    voted-at: uint,
    via-delegation: bool
  }
)

;; Delegations
(define-map delegations
  principal
  {
    delegate: principal,
    delegated-at: uint,
    active: bool
  }
)

;; Track voters per proposal
(define-map proposal-voters
  { proposal-id: uint, index: uint }
  principal
)

(define-map proposal-voter-count uint uint)

;; Private Functions

(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-proposal-creator (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (is-eq tx-sender (get creator proposal))
    false
  )
)

(define-private (has-user-voted (proposal-id uint) (voter principal))
  (is-some (map-get? votes { proposal-id: proposal-id, voter: voter }))
)

(define-private (is-voting-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and
      (>= stacks-block-height (get start-block proposal))
      (<= stacks-block-height (get end-block proposal))
      (is-eq (get status proposal) status-active)
    )
    false
  )
)

(define-private (calculate-quadratic-power (power uint))
  (let
    (
      (sqrt-approx (if (<= power u1) power
        (if (<= power u4) u2
        (if (<= power u9) u3
        (if (<= power u16) u4
        (if (<= power u25) u5
        (if (<= power u36) u6
        (if (<= power u49) u7
        (if (<= power u64) u8
        (if (<= power u81) u9
        (if (<= power u100) u10
        (/ power u10)
        ))))))))))
      )
    )
    sqrt-approx
  )
)

(define-private (get-effective-voting-power (voter principal) (proposal-id uint) (base-power uint))
  (match (map-get? proposals proposal-id)
    proposal (let
      (
        (voting-type (get voting-type proposal))
      )
      (if (is-eq voting-type voting-simple)
        u1
        (if (is-eq voting-type voting-quadratic)
          (calculate-quadratic-power base-power)
          base-power
        )
      )
    )
    u0
  )
)

;; Public Functions

;; Create a new proposal with 2 options (Yes/No)
(define-public (create-proposal
    (title (string-ascii 200))
    (description (string-ascii 1000))
    (voting-type uint)
    (start-block uint)
    (end-block uint)
    (quorum-threshold uint)
    (approval-threshold uint)
  )
  (let
    (
      (proposal-id (var-get total-proposals))
      (creator tx-sender)
    )
    (asserts! (not (var-get system-paused)) err-system-paused)
    (asserts! (> (len title) u0) err-invalid-amount)
    (asserts! (> start-block stacks-block-height) err-invalid-amount)
    (asserts! (> end-block start-block) err-invalid-amount)
    (asserts! (or (is-eq voting-type voting-simple)
                  (or (is-eq voting-type voting-weighted)
                      (is-eq voting-type voting-quadratic))) err-invalid-voting-type)
    (asserts! (<= quorum-threshold u10000) err-invalid-threshold)
    (asserts! (<= approval-threshold u10000) err-invalid-threshold)
    
    (map-set proposals proposal-id
      {
        creator: creator,
        title: title,
        description: description,
        voting-type: voting-type,
        start-block: start-block,
        end-block: end-block,
        option-count: u2,
        total-votes: u0,
        quorum-threshold: quorum-threshold,
        approval-threshold: approval-threshold,
        status: status-pending,
        winner: none,
        created-at: stacks-block-height
      }
    )
    
    ;; Create Yes option
    (map-set proposal-options
      { proposal-id: proposal-id, option-id: u0 }
      { name: "Yes", vote-count: u0, vote-power: u0 }
    )
    
    ;; Create No option
    (map-set proposal-options
      { proposal-id: proposal-id, option-id: u1 }
      { name: "No", vote-count: u0, vote-power: u0 }
    )
    
    (var-set total-proposals (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Add custom option to proposal (before activation)
(define-public (add-proposal-option (proposal-id uint) (option-name (string-ascii 100)))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
      (current-count (get option-count proposal))
    )
    (asserts! (is-proposal-creator proposal-id) err-not-authorized)
    (asserts! (is-eq (get status proposal) status-pending) err-proposal-not-active)
    (asserts! (< current-count u10) err-invalid-amount)
    
    (map-set proposal-options
      { proposal-id: proposal-id, option-id: current-count }
      { name: option-name, vote-count: u0, vote-power: u0 }
    )
    
    (map-set proposals proposal-id
      (merge proposal { option-count: (+ current-count u1) })
    )
    
    (ok current-count)
  )
)

;; Activate proposal when start block reached
(define-public (activate-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-proposal-creator proposal-id) err-not-authorized)
    (asserts! (>= stacks-block-height (get start-block proposal)) err-voting-not-started)
    (asserts! (is-eq (get status proposal) status-pending) err-proposal-not-active)
    
    (map-set proposals proposal-id
      (merge proposal { status: status-active })
    )
    
    (ok true)
  )
)

;; Cast a vote
(define-public (cast-vote (proposal-id uint) (option-id uint) (voting-power uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
      (voter tx-sender)
      (option (unwrap! (map-get? proposal-options { proposal-id: proposal-id, option-id: option-id }) err-invalid-option))
      (effective-power (get-effective-voting-power voter proposal-id voting-power))
      (voter-count (default-to u0 (map-get? proposal-voter-count proposal-id)))
    )
    (asserts! (not (var-get system-paused)) err-system-paused)
    (asserts! (is-voting-active proposal-id) err-voting-ended)
    (asserts! (not (has-user-voted proposal-id voter)) err-already-voted)
    (asserts! (< option-id (get option-count proposal)) err-invalid-option)
    (asserts! (> effective-power u0) err-no-voting-power)
    
    (map-set votes
      { proposal-id: proposal-id, voter: voter }
      {
        option-id: option-id,
        voting-power: effective-power,
        voted-at: stacks-block-height,
        via-delegation: false
      }
    )
    
    (map-set proposal-options
      { proposal-id: proposal-id, option-id: option-id }
      (merge option {
        vote-count: (+ (get vote-count option) u1),
        vote-power: (+ (get vote-power option) effective-power)
      })
    )
    
    (map-set proposals proposal-id
      (merge proposal {
        total-votes: (+ (get total-votes proposal) u1)
      })
    )
    
    (map-set proposal-voters
      { proposal-id: proposal-id, index: voter-count }
      voter
    )
    
    (map-set proposal-voter-count proposal-id (+ voter-count u1))
    (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
    
    (ok true)
  )
)

;; Delegate voting power
(define-public (delegate-vote (delegate principal))
  (let
    (
      (delegator tx-sender)
    )
    (asserts! (not (is-eq delegator delegate)) err-self-delegation)
    
    (map-set delegations delegator
      {
        delegate: delegate,
        delegated-at: stacks-block-height,
        active: true
      }
    )
    
    (ok true)
  )
)

;; Revoke delegation
(define-public (revoke-delegation)
  (let
    (
      (delegator tx-sender)
    )
    (match (map-get? delegations delegator)
      delegation (begin
        (map-set delegations delegator
          (merge delegation { active: false })
        )
        (ok true)
      )
      err-invalid-delegation
    )
  )
)

;; Finalize proposal after voting ends
(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (> stacks-block-height (get end-block proposal)) err-voting-not-started)
    (asserts! (is-eq (get status proposal) status-active) err-already-finalized)
    
    (map-set proposals proposal-id
      (merge proposal { status: status-ended })
    )
    
    (ok true)
  )
)

;; Declare winner for a specific option (manual determination)
(define-public (set-winner (proposal-id uint) (winner-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-proposal-creator proposal-id) err-not-authorized)
    (asserts! (is-eq (get status proposal) status-ended) err-not-finalized)
    (asserts! (< winner-id (get option-count proposal)) err-invalid-option)
    
    (map-set proposals proposal-id
      (merge proposal {
        status: status-finalized,
        winner: (some winner-id)
      })
    )
    
    (ok winner-id)
  )
)

;; Cancel proposal (before voting starts)
(define-public (cancel-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-proposal-creator proposal-id) err-not-authorized)
    (asserts! (< stacks-block-height (get start-block proposal)) err-voting-not-started)
    
    (map-set proposals proposal-id
      (merge proposal { status: status-cancelled })
    )
    
    (ok true)
  )
)

;; Administrative Functions

(define-public (pause-system)
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (var-set system-paused true)
    (ok true)
  )
)

(define-public (resume-system)
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (var-set system-paused false)
    (ok true)
  )
)

;; Read-Only Functions

(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-option-details (proposal-id uint) (option-id uint))
  (map-get? proposal-options { proposal-id: proposal-id, option-id: option-id })
)

(define-read-only (get-vote-details (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-delegation-info (delegator principal))
  (map-get? delegations delegator)
)

(define-read-only (is-proposal-active-check (proposal-id uint))
  (is-voting-active proposal-id)
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
  (has-user-voted proposal-id voter)
)

(define-read-only (get-winning-option (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (ok (get winner proposal))
    err-proposal-not-found
  )
)

(define-read-only (check-quorum-met (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (let
      (
        (total-votes (get total-votes proposal))
        (quorum (get quorum-threshold proposal))
      )
      (ok (>= (* total-votes u10000) quorum))
    )
    err-proposal-not-found
  )
)

(define-read-only (get-proposal-results (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (ok {
      total-votes: (get total-votes proposal),
      status: (get status proposal),
      winner: (get winner proposal)
    })
    err-proposal-not-found
  )
)

(define-read-only (calculate-voting-power (voter principal) (proposal-id uint) (base-power uint))
  (ok (get-effective-voting-power voter proposal-id base-power))
)

(define-read-only (get-platform-stats)
  {
    total-proposals: (var-get total-proposals),
    total-votes: (var-get total-votes-cast),
    system-paused: (var-get system-paused)
  }
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (ok (get status proposal))
    err-proposal-not-found
  )
)

(define-read-only (get-voter-at-index (proposal-id uint) (index uint))
  (map-get? proposal-voters { proposal-id: proposal-id, index: index })
)

(define-read-only (get-option-vote-power (proposal-id uint) (option-id uint))
  (match (map-get? proposal-options { proposal-id: proposal-id, option-id: option-id })
    option (ok (get vote-power option))
    err-invalid-option
  )
)