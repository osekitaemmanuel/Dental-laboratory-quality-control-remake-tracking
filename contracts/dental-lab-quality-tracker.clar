;; Dental Laboratory Quality Control & Remake Tracking System
;; A comprehensive platform for documenting defects, coordinating remakes, 
;; analyzing failure patterns, and improving fabrication quality

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-status (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-data (err u104))

;; Defect severity levels
(define-constant severity-minor u1)
(define-constant severity-moderate u2)
(define-constant severity-major u3)
(define-constant severity-critical u4)

;; Remake status values
(define-constant status-pending u1)
(define-constant status-in-progress u2)
(define-constant status-completed u3)
(define-constant status-verified u4)

;; Data Variables
(define-data-var next-defect-id uint u1)
(define-data-var next-remake-id uint u1)
(define-data-var next-improvement-id uint u1)
(define-data-var total-defects uint u0)
(define-data-var total-remakes uint u0)

;; Data Maps

;; Defect Records
(define-map defects
    { defect-id: uint }
    {
        case-id: (string-ascii 50),
        prosthetic-type: (string-ascii 50),
        defect-type: (string-ascii 100),
        severity: uint,
        technician: principal,
        date-reported: uint,
        root-cause: (string-ascii 200),
        cost-impact: uint,
        reporter: principal
    }
)

;; Remake Tracking
(define-map remakes
    { remake-id: uint }
    {
        defect-id: uint,
        original-case-id: (string-ascii 50),
        status: uint,
        assigned-technician: principal,
        date-initiated: uint,
        date-completed: (optional uint),
        verification-notes: (string-ascii 200),
        remake-cost: uint,
        turnaround-time: uint
    }
)

;; Quality Patterns
(define-map quality-patterns
    { pattern-id: uint }
    {
        defect-type: (string-ascii 100),
        occurrence-count: uint,
        affected-prosthetic-types: (list 10 (string-ascii 50)),
        common-root-causes: (string-ascii 300),
        last-occurrence: uint
    }
)

;; Improvement Initiatives
(define-map improvements
    { improvement-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 300),
        target-defect-type: (string-ascii 100),
        implemented-by: principal,
        implementation-date: uint,
        effectiveness-score: uint,
        defects-before: uint,
        defects-after: uint
    }
)

;; Technician Performance
(define-map technician-stats
    { technician: principal }
    {
        total-cases: uint,
        defect-count: uint,
        remake-count: uint,
        quality-score: uint,
        last-updated: uint
    }
)

;; Defect type counters
(define-map defect-type-counter
    { defect-type: (string-ascii 100) }
    { count: uint }
)

;; Read-only functions

(define-read-only (get-defect (defect-id uint))
    (map-get? defects { defect-id: defect-id })
)

(define-read-only (get-remake (remake-id uint))
    (map-get? remakes { remake-id: remake-id })
)

(define-read-only (get-improvement (improvement-id uint))
    (map-get? improvements { improvement-id: improvement-id })
)

(define-read-only (get-technician-stats (technician principal))
    (map-get? technician-stats { technician: technician })
)

(define-read-only (get-defect-type-count (defect-type (string-ascii 100)))
    (default-to 
        { count: u0 }
        (map-get? defect-type-counter { defect-type: defect-type })
    )
)

(define-read-only (get-total-defects)
    (var-get total-defects)
)

(define-read-only (get-total-remakes)
    (var-get total-remakes)
)

(define-read-only (get-next-defect-id)
    (var-get next-defect-id)
)

;; Public functions

;; Register a new defect
(define-public (register-defect 
    (case-id (string-ascii 50))
    (prosthetic-type (string-ascii 50))
    (defect-type (string-ascii 100))
    (severity uint)
    (technician principal)
    (root-cause (string-ascii 200))
    (cost-impact uint))
    (let
        (
            (defect-id (var-get next-defect-id))
            (current-time block-height)
        )
        ;; Validate severity
        (asserts! (and (>= severity severity-minor) (<= severity severity-critical)) err-invalid-data)
        
        ;; Store defect record
        (map-set defects
            { defect-id: defect-id }
            {
                case-id: case-id,
                prosthetic-type: prosthetic-type,
                defect-type: defect-type,
                severity: severity,
                technician: technician,
                date-reported: current-time,
                root-cause: root-cause,
                cost-impact: cost-impact,
                reporter: tx-sender
            }
        )
        
        ;; Update counters
        (var-set next-defect-id (+ defect-id u1))
        (var-set total-defects (+ (var-get total-defects) u1))
        
        ;; Update defect type counter
        (update-defect-type-counter defect-type)
        
        ;; Update technician stats
        (update-technician-stats technician true)
        
        (ok defect-id)
    )
)

;; Initiate a remake
(define-public (initiate-remake
    (defect-id uint)
    (assigned-technician principal)
    (estimated-cost uint))
    (let
        (
            (remake-id (var-get next-remake-id))
            (defect-data (unwrap! (get-defect defect-id) err-not-found))
            (current-time block-height)
        )
        ;; Store remake record
        (map-set remakes
            { remake-id: remake-id }
            {
                defect-id: defect-id,
                original-case-id: (get case-id defect-data),
                status: status-pending,
                assigned-technician: assigned-technician,
                date-initiated: current-time,
                date-completed: none,
                verification-notes: "",
                remake-cost: estimated-cost,
                turnaround-time: u0
            }
        )
        
        ;; Update counters
        (var-set next-remake-id (+ remake-id u1))
        (var-set total-remakes (+ (var-get total-remakes) u1))
        
        (ok remake-id)
    )
)

;; Update remake status
(define-public (update-remake-status
    (remake-id uint)
    (new-status uint)
    (verification-notes (string-ascii 200)))
    (let
        (
            (remake-data (unwrap! (get-remake remake-id) err-not-found))
            (current-time block-height)
        )
        ;; Validate status
        (asserts! (and (>= new-status status-pending) (<= new-status status-verified)) err-invalid-status)
        
        ;; Update remake record
        (map-set remakes
            { remake-id: remake-id }
            (merge remake-data {
                status: new-status,
                verification-notes: verification-notes,
                date-completed: (if (>= new-status status-completed) 
                    (some current-time) 
                    (get date-completed remake-data)),
                turnaround-time: (if (>= new-status status-completed)
                    (- current-time (get date-initiated remake-data))
                    (get turnaround-time remake-data))
            })
        )
        
        (ok true)
    )
)

;; Record quality improvement initiative
(define-public (record-improvement
    (title (string-ascii 100))
    (description (string-ascii 300))
    (target-defect-type (string-ascii 100))
    (defects-before uint))
    (let
        (
            (improvement-id (var-get next-improvement-id))
            (current-time block-height)
        )
        (map-set improvements
            { improvement-id: improvement-id }
            {
                title: title,
                description: description,
                target-defect-type: target-defect-type,
                implemented-by: tx-sender,
                implementation-date: current-time,
                effectiveness-score: u0,
                defects-before: defects-before,
                defects-after: u0
            }
        )
        
        (var-set next-improvement-id (+ improvement-id u1))
        (ok improvement-id)
    )
)

;; Update improvement effectiveness
(define-public (update-improvement-effectiveness
    (improvement-id uint)
    (defects-after uint)
    (effectiveness-score uint))
    (let
        (
            (improvement-data (unwrap! (get-improvement improvement-id) err-not-found))
        )
        ;; Only implementer can update
        (asserts! (is-eq tx-sender (get implemented-by improvement-data)) err-unauthorized)
        
        (map-set improvements
            { improvement-id: improvement-id }
            (merge improvement-data {
                defects-after: defects-after,
                effectiveness-score: effectiveness-score
            })
        )
        
        (ok true)
    )
)

;; Private helper functions

(define-private (update-defect-type-counter (defect-type (string-ascii 100)))
    (let
        (
            (current-count (get count (get-defect-type-count defect-type)))
        )
        (map-set defect-type-counter
            { defect-type: defect-type }
            { count: (+ current-count u1) }
        )
    )
)

(define-private (update-technician-stats (technician principal) (is-defect bool))
    (let
        (
            (current-stats (default-to
                { total-cases: u0, defect-count: u0, remake-count: u0, quality-score: u100, last-updated: u0 }
                (get-technician-stats technician)))
            (new-defect-count (if is-defect (+ (get defect-count current-stats) u1) (get defect-count current-stats)))
            (new-total-cases (+ (get total-cases current-stats) u1))
            (new-quality-score (if (> new-total-cases u0)
                (- u100 (/ (* new-defect-count u100) new-total-cases))
                u100))
        )
        (map-set technician-stats
            { technician: technician }
            {
                total-cases: new-total-cases,
                defect-count: new-defect-count,
                remake-count: (get remake-count current-stats),
                quality-score: new-quality-score,
                last-updated: block-height
            }
        )
    )
)

;; Calculate quality metrics
(define-read-only (calculate-defect-rate (technician principal))
    (let
        (
            (stats (default-to
                { total-cases: u0, defect-count: u0, remake-count: u0, quality-score: u0, last-updated: u0 }
                (get-technician-stats technician)))
            (total (get total-cases stats))
            (defect-num (get defect-count stats))
        )
        (if (> total u0)
            (ok (/ (* defect-num u100) total))
            (ok u0)
        )
    )
)

;; Get defect severity distribution
(define-read-only (get-quality-score (technician principal))
    (let
        (
            (stats (get-technician-stats technician))
        )
        (match stats
            tech-stats (ok (get quality-score tech-stats))
            (ok u100)
        )
    )
)

