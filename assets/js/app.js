/**
 * LEP Application – Client-side logic
 * Handles cascading dropdowns, project/task loading, validation
 */
(function () {
    'use strict';

    const $ = (sel, ctx = document) => ctx.querySelector(sel);
    const $$ = (sel, ctx = document) => [...ctx.querySelectorAll(sel)];

    // ── Elements ──
    const districtSel   = $('#district_id');
    const blockSel      = $('#block_id');
    const schoolSel     = $('#school_id');
    const udiseInput    = $('#udise_code');
    const gradeSel      = $('#grade_id');
    const subjectSel    = $('#subject_id');
    const subjectWrap   = $('#subjectWrapper');
    const cycleSel      = $('#cycle_id');
    const projectCard      = $('#projectInfoCard');
    const projectTitle     = $('#projectTitle');
    const projectDuration  = $('#projectDuration');
    const projectObjective = $('#projectObjective');
    const projectIdInp     = $('#project_id');
    const downloadBtn      = $('#downloadProjectBtn');
    const notFoundBox      = $('#projectNotFound');
    const notFoundMsg      = $('#projectNotFoundMsg');
    const tasksSection    = $('#tasksSection');
    const tasksContainer  = $('#tasksContainer');
    const evidenceSection = $('#evidenceSection');
    const evidenceInput   = $('#project_evidence');   // final FileList for form submit
    const evidencePicker  = $('#evidencePicker');     // single-file picker
    const addEvidenceBtn  = $('#addEvidenceBtn');
    const evidenceListEl  = $('#evidenceFileList');
    const evidenceListWrap= $('#evidenceListWrap');
    const evidenceCounter = $('#evidenceCounter');
    const evidenceError   = $('#evidenceError');
    const submitBtn       = $('#submitBtn');
    const form            = $('#lepForm');

    let currentProjectId = null;
    let isSchoolLeader   = false;
    let selectedEvidence = [];   // Array of File objects (Gmail-style accumulator)
    const MAX_EVIDENCE   = 5;
    const MAX_TOTAL_BYTES = 5 * 1024 * 1024; // combined size of ALL files ≤ 5 MB
    const ALLOWED_EXT    = ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'];

    // ─────────────────────────────────────────────
    // DISTRICT → BLOCK
    // ─────────────────────────────────────────────
    if (districtSel) {
        districtSel.addEventListener('change', async function () {
            const did = this.value;
            resetSelect(blockSel, '-- Select District first --');
            resetSelect(schoolSel, '-- Select Block first --');
            udiseInput.value = '';
            blockSel.disabled = true;
            schoolSel.disabled = true;

            if (!did) return;

            blockSel.disabled = false;
            blockSel.innerHTML = '<option value="">Loading…</option>';

            try {
                const res = await fetch(`ajax/get_blocks.php?district_id=${did}`);
                const json = await res.json();
                if (!json.success) throw new Error(json.message || 'Failed');

                blockSel.innerHTML = '<option value="">-- Select Block --</option>';
                json.data.forEach(b => {
                    const opt = document.createElement('option');
                    opt.value = b.id;
                    opt.textContent = b.name;
                    blockSel.appendChild(opt);
                });
            } catch (err) {
                blockSel.innerHTML = '<option value="">Error loading blocks</option>';
                console.error(err);
            }
        });
    }

    // ─────────────────────────────────────────────
    // BLOCK → SCHOOL
    // ─────────────────────────────────────────────
    if (blockSel) {
        blockSel.addEventListener('change', async function () {
            const bid = this.value;
            resetSelect(schoolSel, '-- Select Block first --');
            udiseInput.value = '';
            schoolSel.disabled = true;

            if (!bid) return;

            schoolSel.disabled = false;
            schoolSel.innerHTML = '<option value="">Loading…</option>';

            try {
                const res = await fetch(`ajax/get_schools.php?block_id=${bid}`);
                const json = await res.json();
                if (!json.success) throw new Error(json.message || 'Failed');

                schoolSel.innerHTML = '<option value="">-- Select School --</option>';
                json.data.forEach(s => {
                    const opt = document.createElement('option');
                    opt.value = s.id;
                    // Display: School Name (UDISE Code)
                    opt.textContent = s.school_name + ' (' + s.udise_code + ')';
                    opt.dataset.udise = s.udise_code;
                    schoolSel.appendChild(opt);
                });
            } catch (err) {
                schoolSel.innerHTML = '<option value="">Error loading schools</option>';
                console.error(err);
            }
        });
    }

    // ─────────────────────────────────────────────
    // SCHOOL → UDISE
    // ─────────────────────────────────────────────
    if (schoolSel) {
        schoolSel.addEventListener('change', function () {
            const opt = this.options[this.selectedIndex];
            udiseInput.value = opt && opt.dataset.udise ? opt.dataset.udise : '';
        });
    }

    // ─────────────────────────────────────────────
    // GRADE → SUBJECT (or hide for School Leaders)
    // ─────────────────────────────────────────────
    if (gradeSel) {
        gradeSel.addEventListener('change', async function () {
            const gid = this.value;
            const selectedOpt = this.options[this.selectedIndex];
            isSchoolLeader = selectedOpt && selectedOpt.dataset.schoolLeader === '1';

            resetSelect(subjectSel, '-- Select Grade first --');
            clearProjectAndTasks();

            if (!gid) {
                subjectWrap.style.display = '';
                subjectSel.required = true;
                return;
            }

            if (isSchoolLeader) {
                // Hide subject completely
                subjectWrap.style.display = 'none';
                subjectSel.required = false;
                subjectSel.value = '';
                // If cycle already selected, try load project
                if (cycleSel.value) loadProject();
                return;
            }

            // Normal grade – show & load subjects
            subjectWrap.style.display = '';
            subjectSel.required = true;
            subjectSel.innerHTML = '<option value="">Loading…</option>';

            try {
                const res = await fetch(`ajax/get_subjects.php?grade_id=${gid}`);
                const json = await res.json();
                if (!json.success) throw new Error(json.message || 'Failed');

                subjectSel.innerHTML = '<option value="">-- Select Subject --</option>';
                json.data.forEach(s => {
                    const opt = document.createElement('option');
                    opt.value = s.id;
                    opt.textContent = s.name;
                    subjectSel.appendChild(opt);
                });
            } catch (err) {
                subjectSel.innerHTML = '<option value="">Error loading subjects</option>';
                console.error(err);
            }
        });
    }

    // ─────────────────────────────────────────────
    // SUBJECT or CYCLE change → load Project
    // ─────────────────────────────────────────────
    if (subjectSel) {
        subjectSel.addEventListener('change', () => {
            clearProjectAndTasks();
            if (canLoadProject()) loadProject();
        });
    }
    if (cycleSel) {
        cycleSel.addEventListener('change', () => {
            clearProjectAndTasks();
            if (canLoadProject()) loadProject();
        });
    }

    function canLoadProject() {
        if (!gradeSel.value || !cycleSel.value) return false;
        if (isSchoolLeader) return true;
        return !!subjectSel.value;
    }

    async function loadProject() {
        const params = new URLSearchParams({
            grade_id: gradeSel.value,
            cycle_id: cycleSel.value
        });
        if (!isSchoolLeader && subjectSel.value) {
            params.set('subject_id', subjectSel.value);
        }

        projectCard.classList.add('d-none');
        notFoundBox.classList.add('d-none');
        tasksSection.classList.add('d-none');
        if (evidenceSection) evidenceSection.classList.add('d-none');
        tasksContainer.innerHTML = '';
        submitBtn.disabled = true;
        currentProjectId = null;
        projectIdInp.value = '';

        try {
            const res = await fetch(`ajax/get_project.php?${params.toString()}`);
            const json = await res.json();

            if (!json.success) {
                notFoundMsg.textContent = json.message || 'No project found.';
                notFoundBox.classList.remove('d-none');
                setDownloadButton(downloadBtn, null);
                return;
            }

            // Show project info
            const p = json.project;
            projectTitle.textContent = p.title;
            if (projectDuration) projectDuration.textContent = p.duration || '—';
            if (projectObjective) {
                projectObjective.textContent = p.objective || '';
                projectObjective.parentElement.style.display = p.objective ? '' : 'none';
            }
            projectIdInp.value = p.id;
            currentProjectId = p.id;

            const downloadUrl = (p.has_download && p.file)
                ? `download_project.php?id=${p.id}`
                : null;

            // Section B download button (unchanged)
            setDownloadButton(downloadBtn, downloadUrl);

            projectCard.classList.remove('d-none');

            // Render tasks (simplified – Yes/No only)
            renderTasks(json.tasks || []);
            tasksSection.classList.remove('d-none');

            // Show project-level evidence section
            if (evidenceSection) evidenceSection.classList.remove('d-none');

            submitBtn.disabled = false;

        } catch (err) {
            notFoundMsg.textContent = 'Unable to load project. Please try again.';
            notFoundBox.classList.remove('d-none');
            console.error(err);
        }
    }

    function renderTasks(tasks) {
        tasksContainer.innerHTML = '';

        if (!tasks.length) {
            tasksContainer.innerHTML = '<p class="text-muted">No tasks defined for this project.</p>';
            return;
        }

        tasks.forEach((task) => {
            const isShowcase = (task.task_type || 'Task') === 'Showcase';
            const label = isShowcase ? 'Showcase' : ('Task ' + task.task_number);
            const badgeClass = isShowcase
                ? 'task-number-badge flex-shrink-0 bg-warning text-dark'
                : 'task-number-badge flex-shrink-0';
            const badgeText = isShowcase ? 'S' : task.task_number;

            const card = document.createElement('div');
            card.className = 'task-card p-3 mb-3';
            card.innerHTML = `
                <div class="d-flex gap-3 align-items-start">
                    <span class="${badgeClass}">${badgeText}</span>
                    <div class="flex-grow-1">
                        <div class="fw-semibold mb-1">${escapeHtml(label)}</div>
                        <p class="mb-2 task-description lep-readable-text">${escapeHtml(task.task_description)}</p>
                        <div class="task-completed-block">
                            <label class="form-label lep-completed-label required mb-2">Completed?</label>
                            <div class="d-flex flex-wrap gap-2">
                                <div class="form-check lep-radio-option">
                                    <input class="form-check-input" type="radio"
                                           name="task_completed[${task.id}]"
                                           id="comp_yes_${task.id}" value="Yes" required>
                                    <label class="form-check-label" for="comp_yes_${task.id}">Yes</label>
                                </div>
                                <div class="form-check lep-radio-option">
                                    <input class="form-check-input" type="radio"
                                           name="task_completed[${task.id}]"
                                           id="comp_no_${task.id}" value="No" required>
                                    <label class="form-check-label" for="comp_no_${task.id}">No</label>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `;
            tasksContainer.appendChild(card);
        });
    }

    function clearProjectAndTasks() {
        projectCard.classList.add('d-none');
        notFoundBox.classList.add('d-none');
        tasksSection.classList.add('d-none');
        if (evidenceSection) evidenceSection.classList.add('d-none');
        tasksContainer.innerHTML = '';
        projectIdInp.value = '';
        currentProjectId = null;
        submitBtn.disabled = true;

        // Disable Section B download button
        setDownloadButton(downloadBtn, null);

        // Clear evidence accumulator
        selectedEvidence = [];
        syncEvidenceInput();
        renderEvidenceList();

        const videoInp = $('#project_video_link');
        if (videoInp) videoInp.value = '';
    }

    function setDownloadButton(btn, url) {
        if (!btn) return;
        if (url) {
            btn.href = url;
            btn.classList.remove('disabled');
            btn.removeAttribute('aria-disabled');
            btn.removeAttribute('tabindex');
        } else {
            btn.href = '#';
            btn.classList.add('disabled');
            btn.setAttribute('aria-disabled', 'true');
            btn.setAttribute('tabindex', '-1');
        }
    }

    function resetSelect(sel, placeholder) {
        sel.innerHTML = `<option value="">${placeholder}</option>`;
        sel.value = '';
    }

    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    function formatFileSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    }

    // ─────────────────────────────────────────────
    // Gmail-style Evidence Uploader (v1.2)
    // Files are accumulated in selectedEvidence[]
    // and synced to the hidden input via DataTransfer
    // ─────────────────────────────────────────────
    function showEvidenceError(msg) {
        if (!evidenceError) return;
        if (msg) {
            evidenceError.textContent = msg;
            evidenceError.classList.remove('d-none');
        } else {
            evidenceError.textContent = '';
            evidenceError.classList.add('d-none');
        }
    }

    function getTotalEvidenceBytes() {
        return selectedEvidence.reduce((sum, f) => sum + f.size, 0);
    }

    function renderEvidenceList() {
        if (!evidenceListEl) return;

        evidenceListEl.innerHTML = '';
        const totalBytes = getTotalEvidenceBytes();

        if (selectedEvidence.length === 0) {
            if (evidenceListWrap) evidenceListWrap.classList.add('d-none');
            if (evidenceCounter) {
                evidenceCounter.innerHTML = '0 / 5 files selected<br>Total upload size: 0 MB / 5 MB';
            }
            showEvidenceError(null);
            if (addEvidenceBtn) addEvidenceBtn.disabled = false;
            return;
        }

        if (evidenceListWrap) evidenceListWrap.classList.remove('d-none');

        selectedEvidence.forEach((file, idx) => {
            const li = document.createElement('li');
            li.className = 'list-group-item d-flex align-items-center justify-content-between py-2 px-3';
            li.innerHTML = `
                <div class="d-flex align-items-center gap-2 text-truncate me-2">
                    <i class="bi bi-check-circle-fill text-success flex-shrink-0"></i>
                    <span class="text-truncate" title="${escapeHtml(file.name)}">${escapeHtml(file.name)}</span>
                    <span class="text-muted small flex-shrink-0">(${formatFileSize(file.size)})</span>
                </div>
                <button type="button" class="btn btn-sm btn-outline-danger flex-shrink-0 py-0 px-2"
                        data-idx="${idx}" title="Remove">
                    <i class="bi bi-x-lg"></i> Remove
                </button>
            `;
            evidenceListEl.appendChild(li);
        });

        if (evidenceCounter) {
            evidenceCounter.innerHTML =
                selectedEvidence.length + ' / 5 files selected<br>' +
                'Total upload size: ' + formatFileSize(totalBytes) + ' / 5 MB';
        }
        showEvidenceError(null);

        // Disable Add when at file limit OR total size already at/over budget
        if (addEvidenceBtn) {
            addEvidenceBtn.disabled =
                selectedEvidence.length >= MAX_EVIDENCE || totalBytes >= MAX_TOTAL_BYTES;
        }
    }

    function syncEvidenceInput() {
        if (!evidenceInput) return;
        const dt = new DataTransfer();
        selectedEvidence.forEach(f => dt.items.add(f));
        evidenceInput.files = dt.files;
    }

    function addEvidenceFile(file) {
        showEvidenceError(null);

        if (selectedEvidence.length >= MAX_EVIDENCE) {
            showEvidenceError('You may upload a maximum of 5 evidence files.');
            return;
        }

        const ext = file.name.split('.').pop().toLowerCase();
        if (!ALLOWED_EXT.includes(ext)) {
            showEvidenceError('Invalid file type: ' + file.name + '. Allowed: PDF, DOC, DOCX, JPG, JPEG, PNG.');
            return;
        }

        // Combined size check (v1.2.2)
        const currentTotal = getTotalEvidenceBytes();
        if (currentTotal + file.size > MAX_TOTAL_BYTES) {
            showEvidenceError(
                'The total combined size of all uploaded evidence files cannot exceed 5 MB. ' +
                'Please remove one or more files before adding additional evidence.'
            );
            return;
        }

        // Prevent exact duplicate name+size
        const isDup = selectedEvidence.some(f => f.name === file.name && f.size === file.size);
        if (isDup) {
            showEvidenceError('This file is already in the list: ' + file.name);
            return;
        }

        selectedEvidence.push(file);
        syncEvidenceInput();
        renderEvidenceList();
    }

    if (addEvidenceBtn && evidencePicker) {
        addEvidenceBtn.addEventListener('click', function () {
            if (selectedEvidence.length >= MAX_EVIDENCE) {
                showEvidenceError('You may upload a maximum of 5 evidence files.');
                return;
            }
            evidencePicker.value = '';
            evidencePicker.click();
        });

        evidencePicker.addEventListener('change', function () {
            const file = this.files && this.files[0];
            if (file) addEvidenceFile(file);
            this.value = ''; // allow selecting the same file again later if needed
        });
    }

    if (evidenceListEl) {
        evidenceListEl.addEventListener('click', function (e) {
            const btn = e.target.closest('button[data-idx]');
            if (!btn) return;
            const idx = parseInt(btn.dataset.idx, 10);
            if (!isNaN(idx) && idx >= 0 && idx < selectedEvidence.length) {
                selectedEvidence.splice(idx, 1);
                syncEvidenceInput();
                renderEvidenceList();
            }
        });
    }

    // ─────────────────────────────────────────────
    // Form submit validation
    // ─────────────────────────────────────────────
    if (form) {
        form.addEventListener('submit', function (e) {
            // Ensure hidden input has the latest FileList
            syncEvidenceInput();

            if (!form.checkValidity()) {
                e.preventDefault();
                form.classList.add('was-validated');
                const firstInvalid = form.querySelector(':invalid');
                if (firstInvalid) {
                    firstInvalid.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
                return;
            }

            if (!projectIdInp.value) {
                e.preventDefault();
                alert('Please select Grade, Subject (if applicable) and Cycle so that the Project and Tasks are loaded.');
                return;
            }

            if (selectedEvidence.length < 1) {
                e.preventDefault();
                showEvidenceError('Please upload at least one evidence file before submitting your response.');
                if (evidenceSection) {
                    evidenceSection.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
                return;
            }
            if (selectedEvidence.length > MAX_EVIDENCE) {
                e.preventDefault();
                showEvidenceError('You may upload a maximum of 5 evidence files.');
                return;
            }
            if (getTotalEvidenceBytes() > MAX_TOTAL_BYTES) {
                e.preventDefault();
                showEvidenceError(
                    'The total combined size of all uploaded evidence files cannot exceed 5 MB. ' +
                    'Please remove one or more files before submitting.'
                );
                return;
            }

            submitBtn.disabled = true;
            submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Submitting…';
        });
    }

    // Reset button
    const resetBtn = $('#resetBtn');
    if (resetBtn) {
        resetBtn.addEventListener('click', function () {
            if (confirm('Reset the entire form? All entered data will be lost.')) {
                window.location.href = window.location.pathname;
            }
        });
    }

})();
