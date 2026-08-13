<?php
/**
 * Common Footer
 * LEP Application
 */
if (!defined('LEP_APP')) {
    die('Direct access not permitted.');
}
?>
<footer class="lep-footer text-center">
    <div class="container">
        <p class="mb-1">Samagra Shiksha Nagaland | Nagaland Education Mission Society</p>
        <p class="mb-0 small">Government of Nagaland &copy; <?= date('Y') ?> | Learning Enhancement Program (LEP) v<?= APP_VERSION ?></p>
    </div>
</footer>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script src="<?= BASE_URL ?>/assets/js/app.js"></script>
</body>
</html>
