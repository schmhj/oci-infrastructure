#!/usr/bin/env python3
"""Cross-tenancy OKE architecture diagram — Tenant A (acceptor) + Tenant B (requestor).

Polished layout with generous spacing (≥15 px edge-to-icon clearance),
numbered legend table surfacing tooltip details, and white-on-dark edge labels.

Usage:
    python3 generate_tenant_a_drawio.py [output_path]
"""
from __future__ import annotations

import sys
from pathlib import Path

from scripts.diagram.drawio_builder import (
    DrawioBuilder, add_icons_to_map,
    ICON_H, LABEL_GAP, LABEL_H, COLORS,
)

# ---------------------------------------------------------------------------
# Icons beyond the default ICON_MAP
# ---------------------------------------------------------------------------
add_icons_to_map({
    "oke": "developer_services/developer_services_container_engine_for_kubernetes.svg",
    "rpg": "networking/networking_remote_peering_gateway.svg",
})

# ---------------------------------------------------------------------------
# Layout constants — generous spacing edition
# ---------------------------------------------------------------------------
PAD = 15
GAP = 20                         # inter-container gap
ICON_SLOT = 120                  # horizontal icon pitch (was 150)
HEADER = 40                      # container title bar
FOOTER = 20                      # padding below last child
ROW = 50                         # icon row y inside a leaf container
ICON_ROW = ICON_H + LABEL_GAP + LABEL_H   # 142 px — icon + gap + label
ONE_ROW = 210                    # row container height (tight fit, 8 px slack)

# Marker: small numbered badge placed near the top-right of an icon.
MARKER_DX = 55                   # x offset from icon's x to marker centre
MARKER_DY = -10                  # y offset from icon's y (negative = above)

# Legend: panel below the region, 8 entries in a 4×2 grid.
LEGEND_ENTRY_W = 420             # width per legend entry
LEGEND_ENTRY_H = 32              # height per legend entry
LEGEND_COLS = 4
LEGEND_ROWS = 3                  # 10 entries → 4+4+2
LEGEND_W = PAD + LEGEND_COLS * LEGEND_ENTRY_W + PAD   # 20+1680+20 = 1720
LEGEND_H = HEADER + LEGEND_ROWS * LEGEND_ENTRY_H + FOOTER  # 40+96+20 = 156

# ---- container widths -------------------------------------------------------
PUB_W = PAD + 3 * ICON_SLOT + PAD           #  490
PRIV_W = PAD + 4 * ICON_SLOT + PAD          #  640
LPG_W = PAD + 1 * ICON_SLOT + PAD           #  190
BLK_W = PAD + 2 * ICON_SLOT + PAD           #  340
VCN_W = PAD + max(PUB_W, PRIV_W, LPG_W, BLK_W) + PAD  #  680

# ---- VCN heights ------------------------------------------------------------
VCN_A_H = HEADER + 4 * ONE_ROW + 3 * GAP + FOOTER  # 40+920+90+20 = 1070  (now 4 rows — block volumes added)
VCN_B_H = HEADER + 4 * ONE_ROW + 3 * GAP + FOOTER  # 40+920+90+20 = 1070

# ---- Services panel (2×2 grid) ----------------------------------------------
SVC_COLS = 2
SVC_W = PAD + SVC_COLS * ICON_SLOT + PAD     # 340
SVC_H = HEADER + 2 * ICON_ROW + FOOTER        # 344

# ---- Home Network (Tailscale egress, onprem) ---------------------------------
HOME_W = PAD + ICON_SLOT + PAD               #  150
HOME_H = HEADER + 2 * ICON_ROW + FOOTER       #  344

# ---- Internet block (Cloudflare DNS → NLB, onprem) ---------------------------
INET_W = PAD + ICON_SLOT + PAD               #  150
INET_H = HEADER + 3 * ICON_ROW + FOOTER       #  486

# ---- Region: VCN-A | Internet | Home | VCN-B | Services ----------------------
VCN_A_X = PAD                                 #   15
INET_X = VCN_A_X + VCN_W + GAP                #  575
HOME_X = INET_X + INET_W + GAP                #  745
VCN_B_X = HOME_X + HOME_W + GAP               #  915
SVC_X = VCN_B_X + VCN_W + GAP                 # 1475

REGION_W = SVC_X + SVC_W + PAD                # 1760
REGION_H = HEADER + max(VCN_A_H, VCN_B_H, SVC_H, HOME_H, INET_H) + FOOTER

# ---- Legend panel (below region) --------------------------------------------
LEGEND_X = PAD
LEGEND_Y = 0  # computed after region placement

# ---- Page -------------------------------------------------------------------
TITLE_H = 38
TITLE_X, TITLE_Y = PAD, 10
REGION_X, REGION_Y = PAD, TITLE_Y + TITLE_H + GAP   # 15, 68
LEGEND_X = PAD
LEGEND_Y = REGION_Y + REGION_H + GAP                 # 68+1100+20 = 1188
PAGE_W = max(PAD + REGION_W + PAD, 1800)
PAGE_H = max(LEGEND_Y + LEGEND_H + PAD, 1400)

# ---- Edge label style (white text on dark chip) -----------------------------
EDGE_EXTRA = "fontColor=#FFFFFF;labelBackgroundColor=#312D2A;"

# Marker style: small bold circled digit near an icon's top-right.
MARKER_FONT = 12


# ============================================================================
#  Helpers
# ============================================================================
def _marker(d, num: int, icon_x: int, icon_y: int, parent: str) -> str:
    """Place a circled-number badge ①–⑧ near an icon. Returns the cell id."""
    ch = chr(0x245F + num)  # ① = U+2460
    return d.add_text(
        ch, icon_x + MARKER_DX, icon_y + MARKER_DY, w=22, h=18,
        parent=parent, font_size=MARKER_FONT, font_style=1,
        font_color=COLORS["vcn_stroke"],  # Sienna to stand out
        align="center",
    )


# ---- VCN-A private edges: RIGHTWARD (icon order flipped: Wkld, Infra, SGW, NAT)
def _build_private_edges_a(d, wkld, infra, nat, sgw, parent):
    """4 rightward edges in flipped VCN-A (VMs left, gateways right).

    Icon centres (priv-relative): Wkld≈52, Infra≈172, SGW≈292, NAT≈412.
    Gaps: Wkld-Infra≈110, Infra-SGW≈230, SGW-NAT≈350.
    """
    EDGE_SHARP = EDGE_EXTRA + "rounded=0;"
    edges = []

    # 1) wkld → SGW : direct horizontal (no waypoints)
    edges.append(d.add_edge(wkld, sgw, "", parent=parent,
                            style_extra=EDGE_EXTRA))

    # 2) wkld → NAT : exit right → up to y=30 → right to NAT (above icons)
    edges.append(d.add_edge(
        wkld, nat, "", parent=parent,
        exit_x=1.0, exit_y=0.5, entry_x=0.0, entry_y=0.5,
        waypoints=[(110, 97), (110, 30), (412, 30)],
        style_extra=EDGE_SHARP,
    ))

    # 3) infra → SGW : exit right → down to y=180 → right to SGW (below icons)
    edges.append(d.add_edge(
        infra, sgw, "", parent=parent,
        exit_x=1.0, exit_y=0.5, entry_x=0.0, entry_y=0.5,
        waypoints=[(230, 97), (230, 180), (292, 180)],
        style_extra=EDGE_SHARP,
    ))

    # 4) infra → NAT : exit right → down to y=200 → right to NAT (far below)
    edges.append(d.add_edge(
        infra, nat, "", parent=parent,
        exit_x=1.0, exit_y=0.5, entry_x=0.0, entry_y=0.5,
        waypoints=[(230, 97), (230, 200), (412, 200)],
        style_extra=EDGE_SHARP,
    ))
    return edges


# ---- VCN-B private edges: LEFTWARD (unchanged: NAT, SGW, Wk1, Wk2)
def _build_private_edges_b(d, vm1, vm2, nat, sgw, parent):
    """4 leftward edges in VCN-B (gateways left, VMs right).

    Icon centres (priv-relative): NAT≈52, SGW≈172, vm1≈292, vm2≈412.
    Gaps: SGW-vm1≈230, vm1-vm2≈350.
    """
    EDGE_SHARP = EDGE_EXTRA + "rounded=0;"
    edges = []

    # 1) vm1 → SGW : direct horizontal (no waypoints)
    edges.append(d.add_edge(vm1, sgw, "", parent=parent,
                            style_extra=EDGE_EXTRA))

    # 2) vm1 → NAT : exit left → up to y=30 → left to NAT (above icons)
    edges.append(d.add_edge(
        vm1, nat, "", parent=parent,
        exit_x=0.0, exit_y=0.5, entry_x=1.0, entry_y=0.5,
        waypoints=[(230, 97), (230, 30), (52, 30)],
        style_extra=EDGE_SHARP,
    ))

    # 3) vm2 → SGW : exit left → down to y=180 → left to SGW (below icons)
    edges.append(d.add_edge(
        vm2, sgw, "", parent=parent,
        exit_x=0.0, exit_y=0.5, entry_x=1.0, entry_y=0.5,
        waypoints=[(350, 97), (350, 180), (172, 180)],
        style_extra=EDGE_SHARP,
    ))

    # 4) vm2 → NAT : exit left → down to y=200 → left to NAT (far below)
    edges.append(d.add_edge(
        vm2, nat, "", parent=parent,
        exit_x=0.0, exit_y=0.5, entry_x=1.0, entry_y=0.5,
        waypoints=[(350, 97), (350, 200), (52, 200)],
        style_extra=EDGE_SHARP,
    ))
    return edges


# ============================================================================
#  Legend entries: (marker_number, title, detail)
# ============================================================================
LEGEND = [
    ("①", "Infra Node Pool (Tenant A)",
     "1 node · VM.Standard.A1.Flex · 1 OCPU / 8 GB · Taint: tier=infra:NoSchedule"),
    ("②", "Workload Node Pool (Tenant A)",
     "1 node · VM.Standard.A1.Flex · 3 OCPUs / 16 GB · Label: tier=workload"),
    ("③", "Workload Node 1 (Tenant B)",
     "VM.Standard.A1.Flex · 2 OCPUs / 12 GB · Label: tier=workload"),
    ("④", "Workload Node 2 (Tenant B)",
     "VM.Standard.A1.Flex · 2 OCPUs / 12 GB · Label: tier=workload"),
    ("⑤", "Immich Block Volume (Tenant B)",
     "50 GB · Backups enabled · Attached to Workload Node 1"),
    ("⑥", "PostgreSQL Block Volume (Tenant B)",
     "50 GB · Backups enabled · Attached to Workload Node 2"),
    ("⑦", "LPG Acceptor (Tenant A)",
     "Accepts connection from tenant-b · Routes 10.2.0.0/16 via LPG"),
    ("⑧", "LPG Requestor (Tenant B)",
     "Initiates connection to tenant-a · Routes 10.1.0.0/16 via LPG"),
    ("⑨", "App Data Block Volume (Tenant A)",
     "50 GB · Backups enabled · Attached to Workload Node Pool"),
    ("⑩", "App Logs Block Volume (Tenant A)",
     "50 GB · Backups enabled · Attached to Workload Node Pool"),
]


# ============================================================================
def build(out_path: Path) -> None:
    d = DrawioBuilder(
        page_name="Cross-Tenancy OKE — LPG Peering",
        width=PAGE_W, height=PAGE_H,
    )

    # ---- Title ---------------------------------------------------------------
    d.add_text(
        "<b>newyeti — Cross-Tenancy OKE Clusters with LPG Peering (Ashburn)</b><br/>"
        "<i>us-ashburn-1 &nbsp;|&nbsp; "
        "Tenant A: oke-prod-tenant-a (v1.36.1, acceptor) &nbsp;|&nbsp; "
        "Tenant B: oke-prod-tenant-b (v1.36.1, requestor)</i>",
        x=TITLE_X, y=TITLE_Y, w=1500, h=TITLE_H,
        font_size=13, font_style=1,
    )

    # ---- Region --------------------------------------------------------------
    region = d.add_group(
        "Region: Ashburn (us-ashburn-1)",
        REGION_X, REGION_Y, REGION_W, REGION_H,
        group_type="region",
    )

    # ========================================================================
    #  Internet block — Cloudflare DNS → NLB (onprem, between VCN-A and Home)
    # ========================================================================
    inet_block = d.add_group(
        "Internet (Ingress)",
        INET_X, HEADER, INET_W, INET_H,
        parent=region, group_type="onprem",
    )
    inet_anchor = d.add_text("<b>Internet</b>", PAD, ROW, w=ICON_SLOT, h=22,
                             parent=inet_block, font_size=11, font_style=1, align="center")
    cloudflare = d.add_icon("Cloudflare DNS<br/><i>domain → NLB IP</i>", "dns",
                            PAD, ROW + ICON_ROW, parent=inet_block,
                            tooltip="Cloudflare DNS — resolves domain names to NLB public IPs")
    d.add_text("<i>→ NLB<br/>(both VCNs)</i>",
               PAD, ROW + 2 * ICON_ROW, w=ICON_SLOT, h=28,
               parent=inet_block, font_size=9, font_style=2, align="center")

    # ========================================================================
    #  Home Network — Tailscale Egress Proxy (between Internet and VCN-B)
    # ========================================================================
    home = d.add_group(
        "Home Network<br/><i>(Tailscale Egress)</i>",
        HOME_X, HEADER, HOME_W, HOME_H,
        parent=region, group_type="onprem",
    )
    home_cpe = d.add_icon("Home Router / NAS<br/><i>CPE · Tailscale node</i>", "cpe",
                          PAD, ROW, parent=home,
                          tooltip="Tailscale Egress Proxy\n"
                                  "Home network accessible from OCI VCNs via Tailscale mesh VPN")
    d.add_text("<i>Mesh VPN tunnel to<br/>OCI workload nodes</i>",
               PAD, ROW + ICON_ROW, w=ICON_SLOT, h=40,
               parent=home, font_size=9, font_style=2, align="center")

    # ========================================================================
    #  VCN-A  (acceptor) — flipped: gateways face the centre columns
    # ========================================================================
    vcn_a = d.add_group(
        "VCN-A: vcn-schmhj-us-ashburn-1 &nbsp;(10.1.0.0/16) &nbsp;—&nbsp; Acceptor",
        VCN_A_X, HEADER, VCN_W, VCN_A_H,
        parent=region, group_type="vcn",
    )

    # -- Public Subnet A (flipped: OKE, NLB, IGW) ------------------------------
    pub_a = d.add_group(
        "Public Subnet: snet-pub &nbsp;(10.1.0.0/24)",
        PAD, HEADER, PUB_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    oke_a = d.add_icon("OKE API Endpoint<br/><i>public endpoint :6443</i>",
                       "oke",
                       PAD, ROW, parent=pub_a,
                       tooltip="oci_containerengine_cluster\nPublic API endpoint :6443")
    nlb_a = d.add_icon("Network Load Balancer<br/><i>TCP :443 → node :30443</i>",
                       "load_balancer",
                       PAD + ICON_SLOT, ROW, parent=pub_a,
                       tooltip="oci_network_load_balancer\nTCP 443 → node port 30443")
    igw_a = d.add_icon("Internet Gateway<br/><i>0.0.0.0/0 default route</i>",
                       "internet_gateway",
                       PAD + 2 * ICON_SLOT, ROW, parent=pub_a,
                       tooltip="oci_core_internet_gateway\nDefault route 0.0.0.0/0")

    # -- Private Subnet A (flipped: Workload, Infra, SGW, NAT) -----------------
    PRIV_A_Y = HEADER + ONE_ROW + GAP
    priv_a = d.add_group(
        "Private Subnet: snet-priv &nbsp;(10.1.1.0/24)",
        PAD, PRIV_A_Y, PRIV_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    work_a = d.add_icon(
        "Workload Node Pool<br/><i>10.1.1.0/24 · 1×3 OCPU / 16 GB · Tailscale</i>", "vm",
        PAD, ROW, parent=priv_a,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "1 node · VM.Standard.A1.Flex · 3 OCPUs / 16 GB\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "1"},
    )
    infra_a = d.add_icon(
        "Infra Node Pool<br/><i>10.1.1.0/24 · 1×1 OCPU / 8 GB</i>", "vm",
        PAD + ICON_SLOT, ROW, parent=priv_a,
        tooltip="np-schmhj-us-ashburn-1-infra\n"
                "1 node · VM.Standard.A1.Flex · 1 OCPU / 8 GB\n"
                "Taint: tier=infra:NoSchedule",
        metadata={"pool": "infra", "nodes": "1"},
    )
    sgw_a = d.add_icon("Service Gateway<br/><i>all OCI services in region</i>",
                       "service_gateway",
                       PAD + 2 * ICON_SLOT, ROW, parent=priv_a,
                       tooltip="oci_core_service_gateway\nAll OCI services in region")
    nat_a = d.add_icon("NAT Gateway<br/><i>private → public egress</i>",
                       "nat_gateway",
                       PAD + 3 * ICON_SLOT, ROW, parent=priv_a,
                       tooltip="oci_core_nat_gateway\nDefault route 0.0.0.0/0 for private egress")

    # Markers on tenant-A VMs (flipped positions)
    _marker(d, 2, PAD, ROW, priv_a)                      # ② Workload
    _marker(d, 1, PAD + ICON_SLOT, ROW, priv_a)          # ① Infra

    # -- Block Volumes row A ---------------------------------------------------
    BLK_A_Y = PRIV_A_Y + ONE_ROW + GAP
    blk_row_a = d.add_group(
        "Block Volumes",
        PAD, BLK_A_Y, BLK_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    blk1_a = d.add_icon(
        "App Data<br/><i>50 GB block · backups</i>", "block_storage",
        PAD, ROW, parent=blk_row_a,
        tooltip="App Data: 50 GB — backups enabled\nAttached to Workload Node Pool",
        metadata={"size": "50 GB", "app": "App Data", "backup": "enabled"},
    )
    blk2_a = d.add_icon(
        "App Logs<br/><i>50 GB block · backups</i>", "block_storage",
        PAD + ICON_SLOT, ROW, parent=blk_row_a,
        tooltip="App Logs: 50 GB — backups enabled\nAttached to Workload Node Pool",
        metadata={"size": "50 GB", "app": "App Logs", "backup": "enabled"},
    )

    _marker(d, 9, PAD, ROW, blk_row_a)                  # ⑨ App Data
    _marker(d, 10, PAD + ICON_SLOT, ROW, blk_row_a)     # ⑩ App Logs

    # -- LPG Acceptor row A ----------------------------------------------------
    LPG_A_Y = BLK_A_Y + ONE_ROW + GAP
    lpg_row_a = d.add_group(
        "LPG (Acceptor)",
        PAD, LPG_A_Y, LPG_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    lpg_a = d.add_icon("Local Peering Gateway<br/><i>→ 10.2.0.0/16 via LPG</i>", "rpg",
                       PAD, ROW, parent=lpg_row_a,
                       tooltip="oci_core_local_peering_gateway — acceptor\n"
                               "Accepts connection from tenant-b\n"
                               "Routes 10.2.0.0/16 via LPG")
    _marker(d, 7, PAD, ROW, lpg_row_a)  # ⑦ LPG-A

    # ========================================================================
    #  VCN-B  (requestor)
    # ========================================================================
    vcn_b = d.add_group(
        "VCN-B: vcn-schmhj-us-ashburn-1 &nbsp;(10.2.0.0/16) &nbsp;—&nbsp; Requestor",
        VCN_B_X, HEADER, VCN_W, VCN_B_H,
        parent=region, group_type="vcn",
    )

    # -- Public Subnet B -------------------------------------------------------
    pub_b = d.add_group(
        "Public Subnet: snet-pub &nbsp;(10.2.0.0/24)",
        PAD, HEADER, PUB_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    igw_b = d.add_icon("Internet Gateway<br/><i>0.0.0.0/0 default route</i>",
                       "internet_gateway",
                       PAD, ROW, parent=pub_b,
                       tooltip="oci_core_internet_gateway\nDefault route 0.0.0.0/0")
    nlb_b = d.add_icon("Network Load Balancer<br/><i>TCP :443 → node :30443</i>",
                       "load_balancer",
                       PAD + ICON_SLOT, ROW, parent=pub_b,
                       tooltip="oci_network_load_balancer\nTCP 443 → node port 30443")
    oke_b = d.add_icon("OKE API Endpoint<br/><i>public endpoint :6443</i>",
                       "oke",
                       PAD + 2 * ICON_SLOT, ROW, parent=pub_b,
                       tooltip="oci_containerengine_cluster\nPublic API endpoint :6443")
    # -- Private Subnet B ------------------------------------------------------
    PRIV_B_Y = HEADER + ONE_ROW + GAP  # 300
    priv_b = d.add_group(
        "Private Subnet: snet-priv &nbsp;(10.2.1.0/24)",
        PAD, PRIV_B_Y, PRIV_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    nat_b = d.add_icon("NAT Gateway<br/><i>private → public egress</i>",
                       "nat_gateway",
                       PAD, ROW, parent=priv_b,
                       tooltip="oci_core_nat_gateway\nDefault route 0.0.0.0/0 for private egress")
    sgw_b = d.add_icon("Service Gateway<br/><i>all OCI services in region</i>",
                       "service_gateway",
                       PAD + ICON_SLOT, ROW, parent=priv_b,
                       tooltip="oci_core_service_gateway\nAll OCI services in region")
    wk1_b = d.add_icon(
        "Workload Node 1<br/><i>10.2.1.0/24 · 2 OCPU / 12 GB · Tailscale</i>", "vm",
        PAD + 2 * ICON_SLOT, ROW, parent=priv_b,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "2 nodes · VM.Standard.A1.Flex · 2 OCPUs / 12 GB each\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "2"},
    )
    wk2_b = d.add_icon(
        "Workload Node 2<br/><i>10.2.1.0/24 · 2 OCPU / 12 GB · Tailscale</i>", "vm",
        PAD + 3 * ICON_SLOT, ROW, parent=priv_b,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "2 nodes · VM.Standard.A1.Flex · 2 OCPUs / 12 GB each\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "2"},
    )
    # Markers on tenant-B VMs
    _marker(d, 3, PAD + 2 * ICON_SLOT, ROW, priv_b)   # ③ Wk1
    _marker(d, 4, PAD + 3 * ICON_SLOT, ROW, priv_b)   # ④ Wk2

    # -- Block Volumes row B ---------------------------------------------------
    BLK_B_Y = PRIV_B_Y + ONE_ROW + GAP  # 300+230+30 = 560
    blk_row_b = d.add_group(
        "Block Volumes",
        PAD, BLK_B_Y, BLK_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    blk1_b = d.add_icon(
        "Immich<br/><i>50 GB block · backups</i>", "block_storage",
        PAD, ROW, parent=blk_row_b,
        tooltip="Immich: 50 GB — backups enabled\nAttached to Workload Node 1",
        metadata={"size": "50 GB", "app": "Immich", "backup": "enabled"},
    )
    blk2_b = d.add_icon(
        "PostgreSQL<br/><i>50 GB block · backups</i>", "block_storage",
        PAD + ICON_SLOT, ROW, parent=blk_row_b,
        tooltip="PostgreSQL: 50 GB — backups enabled\nAttached to Workload Node 2",
        metadata={"size": "50 GB", "app": "PostgreSQL", "backup": "enabled"},
    )

    _marker(d, 5, PAD, ROW, blk_row_b)                 # ⑤ Immich
    _marker(d, 6, PAD + ICON_SLOT, ROW, blk_row_b)     # ⑥ PostgreSQL

    # -- LPG Requestor row B ---------------------------------------------------
    LPG_B_Y = BLK_B_Y + ONE_ROW + GAP  # 560+230+30 = 820
    lpg_row_b = d.add_group(
        "LPG (Requestor)",
        PAD, LPG_B_Y, LPG_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    lpg_b = d.add_icon("Local Peering Gateway<br/><i>→ 10.1.0.0/16 via LPG</i>", "rpg",
                       PAD, ROW, parent=lpg_row_b,
                       tooltip="oci_core_local_peering_gateway — requestor\n"
                               "Initiates connection to tenant-a LPG\n"
                               "Routes 10.1.0.0/16 via LPG")
    _marker(d, 8, PAD, ROW, lpg_row_b)  # ⑧ LPG-B

    # ========================================================================
    #  OCI Services (shared, 2×2 grid)
    # ========================================================================
    services = d.add_group(
        "OCI Services",
        SVC_X, HEADER, SVC_W, SVC_H,
        parent=region, group_type="services",
    )
    vault = d.add_icon("Vault", "vault",
                       PAD, ROW, parent=services,
                       tooltip="OCI Vault — secrets management")
    devops = d.add_icon("DevOps", "devops",
                        PAD + ICON_SLOT, ROW, parent=services,
                        tooltip="OCI DevOps — CI/CD pipelines")
    logging_icon = d.add_icon("Logging", "logging",
                              PAD, ROW + ICON_ROW, parent=services,
                              tooltip="OCI Logging — centralized log aggregation")
    ocir = d.add_icon("Container Registry", "container_registry",
                      PAD + ICON_SLOT, ROW + ICON_ROW, parent=services,
                      tooltip="OCI Registry (OCIR) — container images")

    # ========================================================================
    #  EDGES
    # ========================================================================
    all_edges = []

    # ---- VCN-A internal edges --------------------------------------------------
    # Private subnet: rightward VM→gateway edges (flipped layout)
    all_edges += _build_private_edges_a(d, work_a, infra_a, nat_a, sgw_a, priv_a)
    # NLB → VMs (cross-subnet, parent=vcn_a)
    all_edges.append(d.add_edge(nlb_a, infra_a, "TCP 30443", parent=vcn_a,
                                style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(nlb_a, work_a, "", parent=vcn_a,
                                style_extra=EDGE_EXTRA))

    # Block-volume attachments VCN-A (work_a vertically aligned with blk1_a)
    # work_a→blk1_a: straight down (same x), no waypoints needed
    all_edges.append(d.add_edge(work_a, blk1_a, "", parent=vcn_a,
                                style_extra=EDGE_EXTRA))
    # work_a→blk2_a: go down through gap at y=480, right to blk2, then down
    all_edges.append(d.add_edge(
        work_a, blk2_a, "", parent=vcn_a,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(67, 480), (187, 480)],
        style_extra=EDGE_EXTRA,
    ))

    # ---- VCN-B internal edges --------------------------------------------------
    # Private subnet: leftward VM→gateway edges (unchanged)
    all_edges += _build_private_edges_b(d, wk1_b, wk2_b, nat_b, sgw_b, priv_b)
    # NLB → VMs
    all_edges.append(d.add_edge(nlb_b, wk1_b, "TCP 30443", parent=vcn_b,
                                style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(nlb_b, wk2_b, "", parent=vcn_b,
                                style_extra=EDGE_EXTRA))

    # Block-volume attachments VCN-B
    all_edges.append(d.add_edge(
        wk1_b, blk1_b, "", parent=vcn_b,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(307, 480), (67, 480)],
        style_extra=EDGE_EXTRA,
    ))
    all_edges.append(d.add_edge(
        wk2_b, blk2_b, "", parent=vcn_b,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(427, 500), (187, 500)],
        style_extra=EDGE_EXTRA,
    ))

    # ---- Internet → IGWs (dashed, parent=region) ------------------------------
    all_edges.append(d.add_edge(inet_anchor, igw_a, "", parent=region,
                                dashed=True, style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(inet_anchor, igw_b, "", parent=region,
                                dashed=True, style_extra=EDGE_EXTRA))

    # ---- Cloudflare DNS → NLBs (solid, parent=region) -------------------------
    all_edges.append(d.add_edge(cloudflare, nlb_a, "DNS → NLB", parent=region,
                                style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(cloudflare, nlb_b, "", parent=region,
                                style_extra=EDGE_EXTRA))

    # ---- LPG peering (parent=region) -----------------------------------------
    all_edges.append(d.add_edge(
        lpg_a, lpg_b, "LPG Peering\n10.1.0.0/16 ↔ 10.2.0.0/16",
        parent=region, style_extra=EDGE_EXTRA,
    ))

    # ---- Tailscale + NAT egress → Home Network (dashed, parent=region) --------
    # Tenant A: NAT → Home (egress) + Workload → Home (Tailscale)
    all_edges.append(d.add_edge(
        nat_a, home_cpe, "Egress", parent=region, dashed=True,
        style_extra=EDGE_EXTRA,
    ))
    all_edges.append(d.add_edge(
        work_a, home_cpe, "Tailscale", parent=region, dashed=True,
        style_extra=EDGE_EXTRA,
    ))
    # Tenant B: NAT → Home (egress) + Workload VMs → Home (Tailscale)
    all_edges.append(d.add_edge(
        nat_b, home_cpe, "Egress", parent=region, dashed=True,
        style_extra=EDGE_EXTRA,
    ))
    all_edges.append(d.add_edge(
        wk1_b, home_cpe, "Tailscale", parent=region, dashed=True,
        style_extra=EDGE_EXTRA,
    ))
    all_edges.append(d.add_edge(
        wk2_b, home_cpe, "", parent=region, dashed=True,
        style_extra=EDGE_EXTRA,
    ))

    # ========================================================================
    #  LEGEND PANEL (below region)
    # ========================================================================
    legend = d.add_group(
        "Resource Details (hover icons for tooltips)",
        LEGEND_X, LEGEND_Y, LEGEND_W, LEGEND_H,
        group_type="services",
    )

    for i, (marker, title, detail) in enumerate(LEGEND):
        col = i % LEGEND_COLS
        row_idx = i // LEGEND_COLS
        lx = PAD + col * LEGEND_ENTRY_W
        ly = HEADER + 4 + row_idx * LEGEND_ENTRY_H  # small top padding inside legend
        d.add_text(
            f"<b>{marker}</b>  {title}<br/><i>{detail}</i>",
            x=lx, y=ly, w=LEGEND_ENTRY_W - 8, h=LEGEND_ENTRY_H,
            parent=legend, font_size=9, font_style=0, align="left",
        )

    # ========================================================================
    #  Overlap gate, write, report
    # ========================================================================
    problems = d.check_overlaps()
    if problems:
        for p in problems:
            print(p)
        raise SystemExit(1)

    d.write(out_path)
    size_kb = out_path.stat().st_size / 1024
    print(
        f"{out_path} | page {PAGE_W}x{PAGE_H} | "
        f"{len(all_edges)} edges | {size_kb:.1f} KB"
    )


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tenant_a_oke_deepdive.drawio")
    build(out)
