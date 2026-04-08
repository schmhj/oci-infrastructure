# Network Load Balancer
# Routes external HTTPS traffic to ArgoCD service on worker nodes
resource "oci_network_load_balancer_network_load_balancer" "nlb" {
  compartment_id = var.compartment_id
  display_name   = local.name_nlb
  subnet_id      = oci_core_subnet.vcn_public_subnet.id

  is_private                     = false
  is_preserve_source_destination = false
}

# Backend Set for Load Balancer
# Defines health check and routing policy
resource "oci_network_load_balancer_backend_set" "nlb_backend_set" {
  name                     = "${local.name_nlb}-backend-set"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false

  # Health check configuration for 10256 (kubelet health check port)
  health_checker {
    protocol = "TCP"
    port     = 10256
  }
}

# Backend pool members (worker nodes)
# Each active node becomes a backend server
resource "oci_network_load_balancer_backend" "nlb_backend" {
  count = var.node_pool_size
  backend_set_name         = oci_network_load_balancer_backend_set.nlb_backend_set.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = var.node_port
  target_id                = data.oci_containerengine_node_pool.oke_np.nodes[count.index].id

  depends_on = [data.oci_containerengine_node_pool.oke_np]
}

# Listener for incoming HTTPS traffic (port 443)
resource "oci_network_load_balancer_listener" "nlb_listener" {
  name                     = "${local.name_nlb}-listener"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = 443
  protocol                 = "TCP"
  default_backend_set_name = oci_network_load_balancer_backend_set.nlb_backend_set.name
}
